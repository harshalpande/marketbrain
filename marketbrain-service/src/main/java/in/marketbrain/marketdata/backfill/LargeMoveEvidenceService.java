package in.marketbrain.marketdata.backfill;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@Service
public class LargeMoveEvidenceService {

    private static final BigDecimal OFFICIAL_MATCH_TOLERANCE_PERCENT = new BigDecimal("0.01");
    private static final List<String> SERIES_PRIORITY = List.of("EQ", "BE", "BZ");

    private final BackfillQualityService qualityService;
    private final NseBhavcopyClient nseClient;
    private final JdbcTemplate jdbcTemplate;

    public LargeMoveEvidenceService(
            BackfillQualityService qualityService,
            NseBhavcopyClient nseClient,
            JdbcTemplate jdbcTemplate
    ) {
        this.qualityService = qualityService;
        this.nseClient = nseClient;
        this.jdbcTemplate = jdbcTemplate;
    }

    public LargeMoveEvidenceReport report(UUID jobId, String requestedSymbol) {
        String symbolFilter = requestedSymbol == null ? null : requestedSymbol.trim().toUpperCase(Locale.ROOT);
        List<BackfillQualityReport.LargeMoveFinding> findings = qualityService.audit(jobId, false).largeMoves().stream()
                .filter(finding -> symbolFilter == null || symbolFilter.isBlank()
                        || finding.symbol().equalsIgnoreCase(symbolFilter))
                .toList();
        if (symbolFilter != null && !symbolFilter.isBlank() && findings.isEmpty()) {
            throw new IllegalArgumentException(
                    "No large-move finding exists for symbol " + symbolFilter + " in backfill job " + jobId);
        }

        Map<String, InstrumentIdentity> identities = instrumentIdentities(jobId);
        Map<SymbolDate, List<String>> corporateActions = corporateActions(jobId);
        Map<java.time.LocalDate, NseBhavcopyArchive> archives = new LinkedHashMap<>();
        findings.stream().map(BackfillQualityReport.LargeMoveFinding::tradingDate).distinct()
                .forEach(date -> archives.put(date, nseClient.fetch(date)));

        List<LargeMoveEvidenceReport.Item> items = new ArrayList<>();
        for (BackfillQualityReport.LargeMoveFinding finding : findings) {
            InstrumentIdentity identity = identities.get(finding.symbol().toUpperCase(Locale.ROOT));
            NseBhavcopyArchive archive = archives.get(finding.tradingDate());
            List<String> actionTypes = corporateActions.getOrDefault(
                    new SymbolDate(finding.symbol().toUpperCase(Locale.ROOT), finding.tradingDate()), List.of());
            items.add(evaluate(finding, identity == null ? null : identity.isin(), archive, actionTypes));
        }

        int officialMatches = count(items, "OFFICIAL_PRICES_MATCH");
        int officialMismatches = (int) items.stream()
                .filter(item -> item.evidenceStatus().startsWith("OFFICIAL_")
                        && item.evidenceStatus().endsWith("MISMATCH"))
                .count();
        int sourceUnavailable = (int) items.stream()
                .filter(item -> List.of("SOURCE_NOT_FOUND", "SOURCE_UNAVAILABLE", "SOURCE_REJECTED",
                        "RATE_LIMITED", "CONNECTION_FAILED", "INVALID_SOURCE_ARCHIVE")
                        .contains(item.evidenceStatus()))
                .count();
        int symbolNotFound = count(items, "OFFICIAL_INSTRUMENT_NOT_FOUND");
        int corporateActionMatches = (int) items.stream()
                .filter(item -> !item.corporateActionTypes().isEmpty())
                .count();

        return new LargeMoveEvidenceReport(
                jobId, items.size(), archives.size(), officialMatches, officialMismatches,
                sourceUnavailable, symbolNotFound, corporateActionMatches, false, List.copyOf(items),
                "Evidence is advisory and read-only. Review each finding before writing an append-only resolution; "
                        + "this endpoint never changes candles, exclusions, or resolution records.");
    }

    LargeMoveEvidenceReport.Item evaluate(
            BackfillQualityReport.LargeMoveFinding finding,
            String isin,
            NseBhavcopyArchive archive,
            List<String> actionTypes
    ) {
        if (!archive.succeeded()) {
            return emptyOfficialItem(finding, isin, archive, actionTypes, archive.status(), "KEEP_OPEN",
                    archive.detail());
        }

        Match match = findOfficialRecord(archive.records(), finding.symbol(), isin);
        if (match == null) {
            return emptyOfficialItem(
                    finding, isin, archive, actionTypes, "OFFICIAL_INSTRUMENT_NOT_FOUND", "KEEP_OPEN",
                    "The official archive was available, but no supported series matched the current symbol or ISIN.");
        }

        NseBhavcopyRecord official = match.record();
        BigDecimal previousDifference = percentDifference(finding.previousClose(), official.previousClose());
        BigDecimal closeDifference = percentDifference(finding.close(), official.close());
        boolean previousMatches = withinTolerance(previousDifference);
        boolean closeMatches = withinTolerance(closeDifference);
        String evidenceStatus = previousMatches && closeMatches ? "OFFICIAL_PRICES_MATCH"
                : closeMatches ? "OFFICIAL_PREVIOUS_CLOSE_MISMATCH" : "OFFICIAL_CLOSE_MISMATCH";
        String reviewPath = !actionTypes.isEmpty() ? "REVIEW_CORPORATE_ACTION_TRANSITION"
                : "OFFICIAL_PRICES_MATCH".equals(evidenceStatus)
                ? "REVIEW_VERIFIED_EXCHANGE_MOVE" : "REVIEW_PROVIDER_ADJUSTMENT";
        String detail = "Official NSE prices were matched by " + match.basis()
                + "; the suggested review path is not a resolution and writes nothing.";

        return new LargeMoveEvidenceReport.Item(
                finding.symbol(), isin, finding.tradingDate(),
                finding.previousClose(), finding.close(), finding.absoluteMovePercent(), evidenceStatus,
                official.symbol(), match.basis(), official.series(), official.previousClose(), official.open(),
                official.high(), official.low(), official.close(), official.volume(), previousDifference,
                closeDifference, actionTypes, reviewPath, archive.format(), archive.sourceUrl(), detail);
    }

    private LargeMoveEvidenceReport.Item emptyOfficialItem(
            BackfillQualityReport.LargeMoveFinding finding,
            String isin,
            NseBhavcopyArchive archive,
            List<String> actionTypes,
            String evidenceStatus,
            String reviewPath,
            String detail
    ) {
        return new LargeMoveEvidenceReport.Item(
                finding.symbol(), isin, finding.tradingDate(),
                finding.previousClose(), finding.close(), finding.absoluteMovePercent(), evidenceStatus,
                null, null, null, null, null, null, null, null, null, null, null,
                actionTypes, reviewPath, archive.format(), archive.sourceUrl(), detail);
    }

    private Match findOfficialRecord(List<NseBhavcopyRecord> records, String symbol, String isin) {
        Comparator<NseBhavcopyRecord> priority = Comparator.comparingInt(
                record -> SERIES_PRIORITY.indexOf(record.series()));
        if (isin != null && !isin.isBlank()) {
            NseBhavcopyRecord byIsin = records.stream()
                    .filter(record -> isin.equalsIgnoreCase(record.isin()))
                    .min(priority)
                    .orElse(null);
            if (byIsin != null) {
                return new Match(byIsin, "ISIN");
            }
        }
        return records.stream()
                .filter(record -> symbol.equalsIgnoreCase(record.symbol()))
                .min(priority)
                .map(record -> new Match(record, "SYMBOL"))
                .orElse(null);
    }

    private Map<String, InstrumentIdentity> instrumentIdentities(UUID jobId) {
        Map<String, InstrumentIdentity> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT chunk.source_symbol, instrument.isin
                FROM historical_backfill_chunk chunk
                JOIN instrument ON instrument.id = chunk.instrument_id
                WHERE chunk.job_id = ?
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> {
            String symbol = rs.getString("source_symbol").toUpperCase(Locale.ROOT);
            result.put(symbol, new InstrumentIdentity(symbol, rs.getString("isin")));
        }, jobId);
        return Map.copyOf(result);
    }

    private Map<SymbolDate, List<String>> corporateActions(UUID jobId) {
        Map<SymbolDate, List<String>> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT chunk.source_symbol, event.effective_on, event.action_type
                FROM historical_backfill_chunk chunk
                JOIN corporate_action_event event ON event.instrument_id = chunk.instrument_id
                WHERE chunk.job_id = ?
                ORDER BY chunk.source_symbol, event.effective_on, event.action_type
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> result.computeIfAbsent(
                        new SymbolDate(rs.getString("source_symbol").toUpperCase(Locale.ROOT),
                                rs.getDate("effective_on").toLocalDate()),
                        ignored -> new ArrayList<>()).add(rs.getString("action_type")), jobId);
        result.replaceAll((key, value) -> List.copyOf(value));
        return Map.copyOf(result);
    }

    private BigDecimal percentDifference(BigDecimal stored, BigDecimal official) {
        if (stored == null || official == null || official.signum() == 0) {
            return null;
        }
        return stored.subtract(official).abs()
                .multiply(new BigDecimal("100"))
                .divide(official.abs(), 4, RoundingMode.HALF_UP);
    }

    private boolean withinTolerance(BigDecimal difference) {
        return difference != null && difference.compareTo(OFFICIAL_MATCH_TOLERANCE_PERCENT) <= 0;
    }

    private int count(List<LargeMoveEvidenceReport.Item> items, String status) {
        return (int) items.stream().filter(item -> status.equals(item.evidenceStatus())).count();
    }

    private record InstrumentIdentity(String symbol, String isin) {
    }

    private record Match(NseBhavcopyRecord record, String basis) {
    }

    private record SymbolDate(String symbol, java.time.LocalDate date) {
    }
}
