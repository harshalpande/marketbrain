package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import in.marketbrain.marketdata.universe.NseEquitySecurity;
import in.marketbrain.marketdata.universe.NseEquitySecurityClient;
import in.marketbrain.marketdata.universe.NseEquitySecurityCsvParser;
import in.marketbrain.marketdata.universe.NseEquitySecuritySourceResult;
import in.marketbrain.marketdata.upstox.UpstoxCandle;
import in.marketbrain.marketdata.upstox.UpstoxFetchResult;
import in.marketbrain.marketdata.upstox.UpstoxHistoricalRequest;
import in.marketbrain.marketdata.upstox.UpstoxReadOnlyClient;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.IOException;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@Service
public class ListingBoundaryEnrichmentService {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");
    private static final long PROVIDER_REQUEST_DELAY_MILLIS = 25L;
    private static final String SOURCE_CODE = "NSE_EQUITY_SECURITY_MASTER";

    private final HistoricalBackfillProperties properties;
    private final HistoricalBackfillJobService jobService;
    private final NseEquitySecurityClient nseClient;
    private final NseEquitySecurityCsvParser nseParser;
    private final UpstoxReadOnlyClient upstoxClient;
    private final YearlyBackfillChunkPlanner chunkPlanner;
    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;

    public ListingBoundaryEnrichmentService(
            HistoricalBackfillProperties properties,
            HistoricalBackfillJobService jobService,
            NseEquitySecurityClient nseClient,
            NseEquitySecurityCsvParser nseParser,
            UpstoxReadOnlyClient upstoxClient,
            YearlyBackfillChunkPlanner chunkPlanner,
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate
    ) {
        this.properties = properties;
        this.jobService = jobService;
        this.nseClient = nseClient;
        this.nseParser = nseParser;
        this.upstoxClient = upstoxClient;
        this.chunkPlanner = chunkPlanner;
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
    }

    public ListingBoundaryEnrichmentReport enrich(int years, int batchSize, String expectedManifestHash) {
        if (properties.workerEnabled()) {
            throw new IllegalStateException(
                    "MARKETBRAIN_BACKFILL_WORKER_ENABLED must remain false during listing-boundary enrichment");
        }
        ExpansionBatchPreview preview = jobService.previewNextExpansionBatch(years, batchSize);
        requireExpectedManifest(preview, expectedManifestHash);

        NseEquitySecuritySourceResult source = nseClient.fetch();
        if (!source.succeeded()) {
            throw new IllegalStateException(source.detail());
        }
        List<NseEquitySecurity> securities;
        try {
            securities = nseParser.parse(new StringReader(
                    new String(source.payload(), StandardCharsets.UTF_8)));
        } catch (IOException | IllegalArgumentException exception) {
            throw new IllegalStateException(
                    "Official NSE equity security metadata failed validation: " + exception.getMessage(), exception);
        }

        List<InstrumentTarget> targets = targets(preview);
        Map<String, NseEquitySecurity> securitiesByIdentity = new HashMap<>();
        for (NseEquitySecurity security : securities) {
            securitiesByIdentity.put(identity(security.symbol(), security.isin()), security);
        }
        List<String> unmatched = targets.stream()
                .filter(target -> !securitiesByIdentity.containsKey(identity(target.symbol(), target.isin())))
                .map(InstrumentTarget::symbol)
                .sorted()
                .toList();
        if (!unmatched.isEmpty()) {
            throw new IllegalStateException(
                    "NSE listing metadata did not match the selected symbol and ISIN for: " + unmatched);
        }

        List<ListingBoundaryEnrichmentReport.Item> items = new ArrayList<>();
        int totalProviderRequests = 0;
        for (InstrumentTarget target : targets) {
            NseEquitySecurity security = securitiesByIdentity.get(identity(target.symbol(), target.isin()));
            Decision decision = decision(target, security, preview.requestedFrom(), source.sha256());
            totalProviderRequests += decision.providerRequestCount();
            items.add(decision.item());
            if ("PROVIDER_CHECK_FAILED".equals(decision.item().reconciliationStatus())) {
                return report(
                        "PROVIDER_CHECK_FAILED", preview, preview.manifestHash(), source, securities.size(),
                        items, totalProviderRequests, 1, 0, 0, false,
                        "A read-only Upstox history check failed. No evidence or boundary was written; retry safely.");
            }
        }

        WriteCounts writes = transactionTemplate.execute(status -> persist(source, items, targets));
        if (writes == null) {
            throw new IllegalStateException("Listing-boundary evidence transaction returned no result");
        }
        ExpansionBatchPreview refreshed = jobService.previewNextExpansionBatch(years, batchSize);
        if (!refreshed.listingEvidenceComplete()) {
            throw new IllegalStateException("Listing evidence was written but the refreshed preview is incomplete");
        }
        return report(
                "COMPLETED", preview, refreshed.manifestHash(), source, securities.size(), items,
                totalProviderRequests, 0, writes.evidenceRows(), writes.boundariesApplied(), true,
                "NSE metadata was preserved as evidence. Only provider-reconciled listing boundaries were applied.");
    }

    private void requireExpectedManifest(ExpansionBatchPreview preview, String expectedManifestHash) {
        if (expectedManifestHash == null || expectedManifestHash.isBlank()) {
            throw new IllegalArgumentException("A reviewed input manifest hash is required");
        }
        if (!preview.manifestHash().equalsIgnoreCase(expectedManifestHash.trim())) {
            throw new IllegalStateException(
                    "The live next-batch selection differs from the supplied manifest; preview it again");
        }
    }

    private List<InstrumentTarget> targets(ExpansionBatchPreview preview) {
        Set<String> selectedSymbols = new HashSet<>();
        preview.instruments().forEach(item -> selectedSymbols.add(item.symbol().toUpperCase(Locale.ROOT)));
        List<InstrumentTarget> result = jdbcTemplate.query("""
                SELECT instrument.id, instrument.symbol, instrument.isin, instrument.listed_on,
                       member.provider_instrument_key, evidence.source_sha256,
                       evidence.reported_listed_on, evidence.provider_prelisting_candle_on,
                       evidence.reconciliation_status, evidence.provider_request_count
                FROM universe_snapshot_member member
                JOIN instrument ON instrument.id = member.instrument_id
                LEFT JOIN LATERAL (
                    SELECT source_sha256, reported_listed_on, provider_prelisting_candle_on,
                           reconciliation_status, provider_request_count
                    FROM instrument_listing_evidence
                    WHERE instrument_id = instrument.id
                    ORDER BY received_at DESC, id DESC
                    LIMIT 1
                ) evidence ON TRUE
                WHERE member.snapshot_id = ? AND member.match_status = 'MATCHED'
                ORDER BY instrument.symbol
                """, (rs, row) -> new InstrumentTarget(
                rs.getLong("id"), rs.getString("symbol"), rs.getString("isin"),
                rs.getString("provider_instrument_key"),
                rs.getDate("listed_on") == null ? null : rs.getDate("listed_on").toLocalDate(),
                rs.getString("source_sha256"),
                rs.getDate("reported_listed_on") == null ? null : rs.getDate("reported_listed_on").toLocalDate(),
                rs.getDate("provider_prelisting_candle_on") == null
                        ? null : rs.getDate("provider_prelisting_candle_on").toLocalDate(),
                rs.getString("reconciliation_status"), rs.getInt("provider_request_count")),
                preview.snapshotId()).stream()
                .filter(item -> selectedSymbols.contains(item.symbol().toUpperCase(Locale.ROOT)))
                .toList();
        if (result.size() != preview.selectedInstruments()) {
            throw new IllegalStateException("The preview instrument identities changed before enrichment");
        }
        return result;
    }

    private Decision decision(
            InstrumentTarget target,
            NseEquitySecurity security,
            LocalDate requestedFrom,
            String sourceSha256
    ) {
        if (sourceSha256.equals(target.evidenceSourceSha256())
                && security.listedOn().equals(target.evidenceReportedListedOn())
                && isAcceptedStatus(target.evidenceStatus())) {
            return decisionItem(
                    target, security, target.evidenceProviderPrelistingCandleOn(), target.evidenceStatus(),
                    target.evidenceProviderRequestCount(), false,
                    "The same NSE source file was already reconciled; its prior decision was retained.");
        }
        if (target.existingListedOn() != null) {
            return decisionItem(target, security, null, "EXISTING_BOUNDARY", 0, false,
                    "An evidence-backed listing boundary already exists and was retained.");
        }
        if (!security.listedOn().isAfter(requestedFrom)) {
            return decisionItem(target, security, null, "BEFORE_REQUEST_WINDOW", 0, false,
                    "The reported NSE security date is before the requested history window; no boundary is needed.");
        }

        ProbeResult probe = probeEarlierHistory(target, requestedFrom, security.listedOn().minusDays(1));
        if (!probe.succeeded()) {
            return decisionItem(target, security, null, "PROVIDER_CHECK_FAILED", probe.requestCount(), false,
                    probe.detail());
        }
        if (probe.candleDate() != null) {
            return decisionItem(target, security, probe.candleDate(), "EARLIER_PROVIDER_HISTORY",
                    probe.requestCount(), false,
                    "Upstox contains history before the reported NSE security date; no truncating boundary was applied.");
        }
        return decisionItem(target, security, null, "VERIFIED_LISTING_BOUNDARY",
                probe.requestCount(), true,
                "No Upstox candle exists before the official NSE security date inside the requested window.");
    }

    private Decision decisionItem(
            InstrumentTarget target,
            NseEquitySecurity security,
            LocalDate providerPrelistingCandleOn,
            String status,
            int providerRequestCount,
            boolean boundaryApplied,
            String detail
    ) {
        return new Decision(new ListingBoundaryEnrichmentReport.Item(
                target.symbol(), target.isin(), security.series(), target.providerInstrumentKey(), security.listedOn(),
                target.existingListedOn(), providerPrelistingCandleOn, status,
                providerRequestCount, boundaryApplied, detail), providerRequestCount);
    }

    private ProbeResult probeEarlierHistory(
            InstrumentTarget target,
            LocalDate requestedFrom,
            LocalDate prelistingTo
    ) {
        List<YearlyBackfillChunkPlanner.DateChunk> chunks = new ArrayList<>(
                chunkPlanner.plan(requestedFrom, prelistingTo));
        Collections.reverse(chunks);
        int requests = 0;
        for (YearlyBackfillChunkPlanner.DateChunk chunk : chunks) {
            requests++;
            UpstoxFetchResult<List<UpstoxCandle>> fetch = upstoxClient.fetchHistoricalCandles(
                    new UpstoxHistoricalRequest(
                            target.providerInstrumentKey(), "days", 1, chunk.fromDate(), chunk.toDate()));
            paceProviderRequests();
            if (!fetch.succeeded()) {
                return new ProbeResult(false, null, requests,
                        "Upstox pre-listing history check failed with " + fetch.status() + ". " + fetch.detail());
            }
            LocalDate detected = fetch.data().stream()
                    .map(candle -> candle.openedAt().atZone(INDIA).toLocalDate())
                    .filter(date -> !date.isBefore(chunk.fromDate()) && !date.isAfter(chunk.toDate()))
                    .min(LocalDate::compareTo)
                    .orElse(null);
            if (detected != null) {
                return new ProbeResult(true, detected, requests, "Earlier provider history detected.");
            }
        }
        return new ProbeResult(true, null, requests, "No earlier provider history detected.");
    }

    private void paceProviderRequests() {
        try {
            Thread.sleep(PROVIDER_REQUEST_DELAY_MILLIS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Listing-boundary provider checks were interrupted", exception);
        }
    }

    private WriteCounts persist(
            NseEquitySecuritySourceResult source,
            List<ListingBoundaryEnrichmentReport.Item> items,
            List<InstrumentTarget> targets
    ) {
        Map<String, Long> idsBySymbol = new HashMap<>();
        targets.forEach(target -> idsBySymbol.put(target.symbol(), target.instrumentId()));
        int evidenceRows = 0;
        int boundariesApplied = 0;
        for (ListingBoundaryEnrichmentReport.Item item : items) {
            Long instrumentId = idsBySymbol.get(item.symbol());
            evidenceRows += jdbcTemplate.update("""
                    INSERT INTO instrument_listing_evidence
                        (instrument_id, source_code, source_url, source_sha256,
                         source_symbol, source_isin, source_series, reported_listed_on,
                         provider_prelisting_candle_on, reconciliation_status, provider_request_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (instrument_id, source_sha256, source_series) DO UPDATE SET
                        source_url = EXCLUDED.source_url,
                        source_symbol = EXCLUDED.source_symbol,
                        source_isin = EXCLUDED.source_isin,
                        reported_listed_on = EXCLUDED.reported_listed_on,
                        provider_prelisting_candle_on = EXCLUDED.provider_prelisting_candle_on,
                        reconciliation_status = EXCLUDED.reconciliation_status,
                        provider_request_count = EXCLUDED.provider_request_count,
                        received_at = CURRENT_TIMESTAMP
                    """, instrumentId, SOURCE_CODE, properties.nseEquitySecurityUrl(), source.sha256(),
                    item.symbol(), item.isin(), item.nseSeries(), Date.valueOf(item.nseReportedListedOn()),
                    dateOrNull(item.providerPrelistingCandleOn()), item.reconciliationStatus(),
                    item.providerRequestCount());
            if ("VERIFIED_LISTING_BOUNDARY".equals(item.reconciliationStatus())) {
                int updated = jdbcTemplate.update("""
                        UPDATE instrument
                        SET listed_on = ?, listing_date_source_url = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE id = ? AND listed_on IS NULL
                        """, Date.valueOf(item.nseReportedListedOn()),
                        properties.nseEquitySecurityUrl(), instrumentId);
                if (updated == 0) {
                    LocalDate current = jdbcTemplate.queryForObject(
                            "SELECT listed_on FROM instrument WHERE id = ?", LocalDate.class, instrumentId);
                    if (!item.nseReportedListedOn().equals(current)) {
                        throw new IllegalStateException(
                                "A conflicting listing boundary appeared for " + item.symbol());
                    }
                } else {
                    boundariesApplied++;
                }
            }
        }
        return new WriteCounts(evidenceRows, boundariesApplied);
    }

    private ListingBoundaryEnrichmentReport report(
            String status,
            ExpansionBatchPreview preview,
            String outputManifestHash,
            NseEquitySecuritySourceResult source,
            int sourceRecords,
            List<ListingBoundaryEnrichmentReport.Item> items,
            int providerRequests,
            int providerFailures,
            int evidenceRows,
            int boundariesApplied,
            boolean evidenceComplete,
            String detail
    ) {
        return new ListingBoundaryEnrichmentReport(
                status, preview.snapshotId(), preview.batchNumber(), preview.manifestHash(), outputManifestHash,
                properties.nseEquitySecurityUrl(), source.sha256(), sourceRecords,
                preview.selectedInstruments(), items.size(), count(items, "BEFORE_REQUEST_WINDOW"),
                count(items, "EXISTING_BOUNDARY"), count(items, "VERIFIED_LISTING_BOUNDARY"),
                count(items, "EARLIER_PROVIDER_HISTORY"), providerRequests, providerFailures,
                evidenceRows, boundariesApplied, evidenceComplete, evidenceRows > 0,
                items, detail);
    }

    private int count(List<ListingBoundaryEnrichmentReport.Item> items, String status) {
        return (int) items.stream().filter(item -> status.equals(item.reconciliationStatus())).count();
    }

    private boolean isAcceptedStatus(String status) {
        return status != null && Set.of(
                "BEFORE_REQUEST_WINDOW", "EXISTING_BOUNDARY",
                "VERIFIED_LISTING_BOUNDARY", "EARLIER_PROVIDER_HISTORY").contains(status);
    }

    private String identity(String symbol, String isin) {
        return symbol.toUpperCase(Locale.ROOT) + "|" + isin.toUpperCase(Locale.ROOT);
    }

    private Date dateOrNull(LocalDate value) {
        return value == null ? null : Date.valueOf(value);
    }

    private record InstrumentTarget(
            long instrumentId,
            String symbol,
            String isin,
            String providerInstrumentKey,
            LocalDate existingListedOn,
            String evidenceSourceSha256,
            LocalDate evidenceReportedListedOn,
            LocalDate evidenceProviderPrelistingCandleOn,
            String evidenceStatus,
            int evidenceProviderRequestCount
    ) {
    }

    private record Decision(ListingBoundaryEnrichmentReport.Item item, int providerRequestCount) {
    }

    private record ProbeResult(boolean succeeded, LocalDate candleDate, int requestCount, String detail) {
    }

    private record WriteCounts(int evidenceRows, int boundariesApplied) {
    }
}
