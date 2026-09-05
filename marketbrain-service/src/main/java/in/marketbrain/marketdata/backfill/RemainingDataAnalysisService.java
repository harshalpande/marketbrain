package in.marketbrain.marketdata.backfill;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;

@Service
public class RemainingDataAnalysisService {

    private static final List<String> SOURCE_FAILURES = List.of(
            "SOURCE_NOT_FOUND", "SOURCE_UNAVAILABLE", "SOURCE_REJECTED",
            "RATE_LIMITED", "CONNECTION_FAILED", "INVALID_SOURCE_ARCHIVE");

    private final BackfillQualityService qualityService;
    private final NseBhavcopyClient nseClient;
    private final LargeMoveEvidenceService largeMoveEvidenceService;
    private final JdbcTemplate jdbcTemplate;

    public RemainingDataAnalysisService(
            BackfillQualityService qualityService,
            NseBhavcopyClient nseClient,
            LargeMoveEvidenceService largeMoveEvidenceService,
            JdbcTemplate jdbcTemplate
    ) {
        this.qualityService = qualityService;
        this.nseClient = nseClient;
        this.largeMoveEvidenceService = largeMoveEvidenceService;
        this.jdbcTemplate = jdbcTemplate;
    }

    public RemainingDataAnalysisReport analyze(UUID jobId) {
        BackfillQualityReport quality = qualityService.audit(jobId, false);
        if (quality.truncatedFindingCount() != 0) {
            throw new IllegalStateException("The quality finding set is truncated; a complete plan cannot be produced");
        }
        List<BackfillQualityReport.QualityFinding> unresolved = quality.qualityFindings().stream()
                .filter(finding -> !finding.allowsTraining())
                .toList();

        Map<String, String> currentIsins = currentIsins(jobId);
        Map<String, List<LargeMoveEvidenceService.HistoricalIdentity>> historicalIdentities =
                historicalIdentities(jobId);
        Map<String, OfficialListingBoundary> officialListingBoundaries = officialListingBoundaries(jobId);
        Map<SymbolDate, BackfillQualityReport.LargeMoveFinding> largeMoves = new HashMap<>();
        quality.largeMoves().forEach(move -> largeMoves.put(
                new SymbolDate(move.symbol().toUpperCase(Locale.ROOT), move.tradingDate()), move));

        Map<LocalDate, List<BackfillQualityReport.QualityFinding>> sourceFindingsByDate = new TreeMap<>();
        List<RemainingDataAnalysisReport.Item> items = new ArrayList<>();
        for (BackfillQualityReport.QualityFinding finding : unresolved) {
            if (requiresOfficialArchive(finding)) {
                sourceFindingsByDate.computeIfAbsent(finding.findingDate(), ignored -> new ArrayList<>())
                        .add(finding);
            } else {
                items.add(analyzeCoverageGap(finding));
            }
        }

        for (Map.Entry<LocalDate, List<BackfillQualityReport.QualityFinding>> entry
                : sourceFindingsByDate.entrySet()) {
            NseBhavcopyArchive archive = nseClient.fetch(entry.getKey());
            for (BackfillQualityReport.QualityFinding finding : entry.getValue()) {
                String symbolKey = finding.symbol() == null ? null : finding.symbol().toUpperCase(Locale.ROOT);
                String isin = symbolKey == null ? null : currentIsins.get(symbolKey);
                List<LargeMoveEvidenceService.HistoricalIdentity> aliases = symbolKey == null
                        ? List.of() : historicalIdentities.getOrDefault(symbolKey, List.of());
                items.add(switch (finding.findingType()) {
                    case OFFICIAL_SPECIAL_SESSION, PEER_CONFIRMED_SESSION -> analyzeMissingSession(
                            finding, isin, aliases, archive);
                    case LARGE_MOVE -> analyzeLargeMove(
                            finding, isin, aliases, archive, largeMoves.get(
                                    new SymbolDate(symbolKey, finding.findingDate())),
                            officialListingBoundaries.get(symbolKey));
                    case LEADING_COVERAGE_GAP, TRAILING_COVERAGE_GAP, SUSPICIOUS_GAP ->
                            throw new IllegalStateException("Coverage finding was assigned to an NSE archive");
                });
            }
        }

        List<RemainingDataAnalysisReport.Item> sortedItems = items.stream()
                .sorted(Comparator.comparing((RemainingDataAnalysisReport.Item item) -> item.findingType().name())
                        .thenComparing(RemainingDataAnalysisReport.Item::findingDate)
                        .thenComparing(item -> item.symbol() == null ? "" : item.symbol()))
                .toList();
        int keepOpen = (int) sortedItems.stream()
                .filter(item -> item.recommendedResolutionType() == null)
                .count();
        int sourceFailures = (int) sortedItems.stream()
                .filter(item -> SOURCE_FAILURES.contains(item.analysisStatus()))
                .count();
        boolean complete = keepOpen == 0 && sourceFailures == 0
                && sortedItems.size() == quality.unresolvedFindingCount();

        return new RemainingDataAnalysisReport(
                jobId, sortedItems.size(), countType(sortedItems, QualityFindingType.OFFICIAL_SPECIAL_SESSION),
                countType(sortedItems, QualityFindingType.PEER_CONFIRMED_SESSION),
                countCoverageGaps(sortedItems), countType(sortedItems, QualityFindingType.LARGE_MOVE),
                sourceFindingsByDate.size(),
                countResolution(sortedItems, QualityResolutionType.SECONDARY_SOURCE_BACKFILLED),
                countResolution(sortedItems, QualityResolutionType.FEATURE_WINDOW_EXCLUDED),
                countResolution(sortedItems, QualityResolutionType.PROVIDER_ADJUSTMENT),
                countResolution(sortedItems, QualityResolutionType.VERIFIED_EXCHANGE_MOVE),
                keepOpen, sourceFailures, complete, planHash(sortedItems), false, false, sortedItems,
                "The plan is read-only. Step 21 may apply the reviewed hash through checkpointed, idempotent "
                        + "per-finding operations; this analysis never changes candles, exclusions, or resolutions.");
    }

    RemainingDataAnalysisReport.Item analyzeMissingSession(
            BackfillQualityReport.QualityFinding finding,
            String isin,
            List<LargeMoveEvidenceService.HistoricalIdentity> aliases,
            NseBhavcopyArchive archive
    ) {
        if (archive == null || !archive.succeeded()) {
            String status = archive == null ? "SOURCE_UNAVAILABLE" : archive.status();
            String url = archive == null ? null : archive.sourceUrl();
            return item(finding, status, null, null, null, null,
                    null, null, null, null, null, null, null, null, null,
                    "NSE official daily BhavCopy", url,
                    "The official archive was unavailable; keep this finding open and retry the analysis.");
        }
        LargeMoveEvidenceService.Match match = largeMoveEvidenceService.findOfficialRecord(
                archive.records(), finding.symbol(), isin, aliases, finding.findingDate());
        if (match == null) {
            return item(finding, "OFFICIAL_INSTRUMENT_NOT_FOUND", QualityResolutionType.FEATURE_WINDOW_EXCLUDED,
                    finding.findingDate(), finding.findingDate(), null,
                    null, null, null, null, null, null, null, null, null,
                    "NSE official daily BhavCopy", archive.sourceUrl(),
                    "The exchange file contains no supported record for this identity; exclude this one session "
                            + "instead of inventing a candle.");
        }
        NseBhavcopyRecord official = match.record();
        if (!validCandle(official)) {
            return item(finding, "OFFICIAL_CANDLE_INVALID", null, null, null,
                    official.symbol(), match.basis(), official.series(), official.open(), official.high(),
                    official.low(), official.close(), official.volume(), null, null,
                    "NSE official daily BhavCopy", archive.sourceUrl(),
                    "The official row failed OHLC completeness or ordering validation; keep it open.");
        }
        return item(finding, "OFFICIAL_CANDLE_AVAILABLE", QualityResolutionType.SECONDARY_SOURCE_BACKFILLED,
                null, null, official.symbol(), match.basis(), official.series(), official.open(), official.high(),
                official.low(), official.close(), official.volume(), null, null,
                "NSE official daily BhavCopy", archive.sourceUrl(),
                "Step 21 can insert this missing daily candle under a separate NSE official source and then "
                        + "append its governed resolution.");
    }

    RemainingDataAnalysisReport.Item analyzeLargeMove(
            BackfillQualityReport.QualityFinding finding,
            String isin,
            List<LargeMoveEvidenceService.HistoricalIdentity> aliases,
            NseBhavcopyArchive archive,
            BackfillQualityReport.LargeMoveFinding move,
            OfficialListingBoundary officialListingBoundary
    ) {
        if (move == null || archive == null) {
            return item(finding, "MISSING_LARGE_MOVE_CONTEXT", null, null, null,
                    null, null, null, null, null, null, null, null, null, null,
                    "NSE official daily BhavCopy", archive == null ? null : archive.sourceUrl(),
                    "The current audit did not expose enough context to resolve this finding.");
        }
        LargeMoveEvidenceReport.Item evidence = largeMoveEvidenceService.evaluate(
                move, isin, aliases, archive, finding.corporateActionTypes());
        QualityResolutionType resolutionType;
        LocalDate exclusionFrom = null;
        LocalDate exclusionTo = null;
        if (List.of("OFFICIAL_PRICES_MATCH", "OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES")
                .contains(evidence.evidenceStatus())) {
            resolutionType = QualityResolutionType.VERIFIED_EXCHANGE_MOVE;
        } else if (evidence.evidenceStatus().endsWith("MISMATCH")) {
            resolutionType = QualityResolutionType.PROVIDER_ADJUSTMENT;
            exclusionFrom = finding.findingDate();
            exclusionTo = finding.findingDate();
        } else if ("OFFICIAL_INSTRUMENT_NOT_FOUND".equals(evidence.evidenceStatus())
                && officialListingBoundary != null
                && finding.findingDate().isBefore(officialListingBoundary.reportedListedOn())) {
            resolutionType = QualityResolutionType.FEATURE_WINDOW_EXCLUDED;
            exclusionFrom = finding.findingDate();
            exclusionTo = finding.findingDate();
        } else {
            resolutionType = null;
        }
        boolean prelistingExclusion = resolutionType == QualityResolutionType.FEATURE_WINDOW_EXCLUDED;
        return item(finding, evidence.evidenceStatus(), resolutionType, exclusionFrom, exclusionTo,
                evidence.officialSymbol(), evidence.matchBasis(), evidence.officialSeries(),
                evidence.officialOpen(), evidence.officialHigh(), evidence.officialLow(), evidence.officialClose(),
                evidence.officialVolume(), evidence.storedReturnPercent(), evidence.officialReturnPercent(),
                prelistingExclusion
                        ? "NSE listing metadata and official daily BhavCopy"
                        : "NSE official daily BhavCopy",
                prelistingExclusion ? officialListingBoundary.evidenceUrl() : evidence.sourceUrl(),
                resolutionType == QualityResolutionType.PROVIDER_ADJUSTMENT
                        ? "Stored and official returns differ beyond tolerance; preserve the candle for audit but "
                        + "exclude this transition date from model features and backtests."
                        : prelistingExclusion
                        ? "The current and reviewed historical identities are absent from the official archive "
                        + "before the NSE-reported listing date; exclude only this finding date without rewriting "
                        + "or inventing a candle."
                        : evidence.detail());
    }

    RemainingDataAnalysisReport.Item analyzeCoverageGap(BackfillQualityReport.QualityFinding finding) {
        LocalDate from;
        LocalDate to;
        if (finding.findingType() == QualityFindingType.LEADING_COVERAGE_GAP) {
            from = finding.findingDate();
            to = finding.relatedDate() == null ? finding.findingDate() : finding.relatedDate().minusDays(1);
        } else if (finding.findingType() == QualityFindingType.TRAILING_COVERAGE_GAP) {
            from = finding.relatedDate() == null ? finding.findingDate() : finding.relatedDate().plusDays(1);
            to = finding.findingDate();
        } else {
            from = finding.relatedDate() == null ? finding.findingDate() : finding.relatedDate();
            to = finding.findingDate();
        }
        if (to.isBefore(from)) {
            to = from;
        }
        return item(finding, "COVERAGE_WINDOW_REQUIRES_EXCLUSION", QualityResolutionType.FEATURE_WINDOW_EXCLUDED,
                from, to, null, null, null, null, null, null, null, null, null, null,
                "MarketBrain persisted coverage audit", null,
                "No candle is invented. Step 21 can exclude the unavailable window from features and backtests "
                        + "while retaining the raw provider coverage boundary.");
    }

    private RemainingDataAnalysisReport.Item item(
            BackfillQualityReport.QualityFinding finding,
            String status,
            QualityResolutionType resolutionType,
            LocalDate exclusionFrom,
            LocalDate exclusionTo,
            String officialSymbol,
            String matchBasis,
            String officialSeries,
            BigDecimal officialOpen,
            BigDecimal officialHigh,
            BigDecimal officialLow,
            BigDecimal officialClose,
            BigDecimal officialVolume,
            BigDecimal storedReturn,
            BigDecimal officialReturn,
            String evidenceSource,
            String evidenceUrl,
            String detail
    ) {
        BigDecimal returnDifference = storedReturn == null || officialReturn == null
                ? null : storedReturn.subtract(officialReturn).abs();
        return new RemainingDataAnalysisReport.Item(
                finding.findingType(), finding.symbol(), finding.findingDate(), finding.relatedDate(), status,
                resolutionType, exclusionFrom, exclusionTo, officialSymbol, matchBasis, officialSeries,
                officialOpen, officialHigh, officialLow, officialClose, officialVolume,
                storedReturn, officialReturn, returnDifference, evidenceSource, evidenceUrl, detail);
    }

    private boolean requiresOfficialArchive(BackfillQualityReport.QualityFinding finding) {
        return finding.findingType() == QualityFindingType.OFFICIAL_SPECIAL_SESSION
                || finding.findingType() == QualityFindingType.PEER_CONFIRMED_SESSION
                || finding.findingType() == QualityFindingType.LARGE_MOVE;
    }

    private boolean validCandle(NseBhavcopyRecord record) {
        return record.open() != null && record.high() != null && record.low() != null && record.close() != null
                && record.open().signum() > 0 && record.high().signum() > 0
                && record.low().signum() > 0 && record.close().signum() > 0
                && record.low().compareTo(record.open()) <= 0 && record.low().compareTo(record.close()) <= 0
                && record.high().compareTo(record.open()) >= 0 && record.high().compareTo(record.close()) >= 0
                && (record.volume() == null || record.volume().signum() >= 0);
    }

    private Map<String, String> currentIsins(UUID jobId) {
        Map<String, String> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT chunk.source_symbol, instrument.isin
                FROM historical_backfill_chunk chunk
                JOIN instrument ON instrument.id = chunk.instrument_id
                WHERE chunk.job_id = ?
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> result.put(
                        rs.getString("source_symbol").toUpperCase(Locale.ROOT), rs.getString("isin")), jobId);
        return Map.copyOf(result);
    }

    private Map<String, List<LargeMoveEvidenceService.HistoricalIdentity>> historicalIdentities(UUID jobId) {
        Map<String, List<LargeMoveEvidenceService.HistoricalIdentity>> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT alias.current_symbol, alias.alias_symbol, alias.alias_isin,
                       alias.effective_from, alias.effective_to
                FROM instrument_identity_alias alias
                JOIN historical_backfill_chunk chunk
                  ON UPPER(chunk.source_symbol) = UPPER(alias.current_symbol)
                WHERE chunk.job_id = ? AND alias.exchange = 'NSE'
                ORDER BY alias.current_symbol, alias.effective_from, alias.effective_to
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> result.computeIfAbsent(
                        rs.getString("current_symbol").toUpperCase(Locale.ROOT),
                        ignored -> new ArrayList<>()).add(new LargeMoveEvidenceService.HistoricalIdentity(
                                rs.getString("alias_symbol"), rs.getString("alias_isin"),
                                rs.getDate("effective_from").toLocalDate(),
                                rs.getDate("effective_to").toLocalDate())), jobId);
        result.replaceAll((key, value) -> List.copyOf(value));
        return Map.copyOf(result);
    }

    private Map<String, OfficialListingBoundary> officialListingBoundaries(UUID jobId) {
        Map<String, OfficialListingBoundary> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT chunk.source_symbol, evidence.reported_listed_on, evidence.source_url
                FROM historical_backfill_chunk chunk
                JOIN LATERAL (
                    SELECT listing.reported_listed_on, listing.source_url
                    FROM instrument_listing_evidence listing
                    WHERE listing.instrument_id = chunk.instrument_id
                    ORDER BY listing.received_at DESC, listing.id DESC
                    LIMIT 1
                ) evidence ON TRUE
                WHERE chunk.job_id = ?
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> result.put(
                        rs.getString("source_symbol").toUpperCase(Locale.ROOT),
                        new OfficialListingBoundary(
                                rs.getDate("reported_listed_on").toLocalDate(),
                                rs.getString("source_url"))), jobId);
        return Map.copyOf(result);
    }

    private int countType(List<RemainingDataAnalysisReport.Item> items, QualityFindingType type) {
        return (int) items.stream().filter(item -> item.findingType() == type).count();
    }

    private int countCoverageGaps(List<RemainingDataAnalysisReport.Item> items) {
        return (int) items.stream().filter(item -> List.of(
                QualityFindingType.LEADING_COVERAGE_GAP,
                QualityFindingType.TRAILING_COVERAGE_GAP,
                QualityFindingType.SUSPICIOUS_GAP).contains(item.findingType())).count();
    }

    private int countResolution(
            List<RemainingDataAnalysisReport.Item> items,
            QualityResolutionType resolutionType
    ) {
        return (int) items.stream().filter(item -> item.recommendedResolutionType() == resolutionType).count();
    }

    private String planHash(List<RemainingDataAnalysisReport.Item> items) {
        String canonical = items.stream().map(this::canonicalItem).sorted().reduce(
                (left, right) -> left + "\n" + right).orElse("");
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(canonical.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available", exception);
        }
    }

    private String canonicalItem(RemainingDataAnalysisReport.Item item) {
        return String.join("|",
                item.findingType().name(), value(item.symbol()), value(item.findingDate()),
                value(item.relatedDate()), item.analysisStatus(),
                item.recommendedResolutionType() == null ? "" : item.recommendedResolutionType().name(),
                value(item.exclusionFrom()), value(item.exclusionTo()), value(item.officialSymbol()),
                value(item.matchBasis()), value(item.officialSeries()), value(item.officialOpen()),
                value(item.officialHigh()), value(item.officialLow()), value(item.officialClose()),
                value(item.officialVolume()), value(item.storedReturnPercent()),
                value(item.officialReturnPercent()), value(item.returnDifferencePercentagePoints()),
                value(item.evidenceSource()), value(item.evidenceUrl()));
    }

    private String value(Object value) {
        if (value instanceof BigDecimal decimal) {
            return decimal.stripTrailingZeros().toPlainString();
        }
        return value == null ? "" : value.toString();
    }

    private record SymbolDate(String symbol, LocalDate date) {
    }

    record OfficialListingBoundary(LocalDate reportedListedOn, String evidenceUrl) {
    }
}
