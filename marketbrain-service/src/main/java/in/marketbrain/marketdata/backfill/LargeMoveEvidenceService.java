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
    private static final BigDecimal ADJUSTED_RETURN_TOLERANCE_PERCENTAGE_POINTS = new BigDecimal("0.50");
    private static final BigDecimal ADJUSTED_SCALE_TOLERANCE_PERCENT = new BigDecimal("0.50");
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
        Map<String, List<HistoricalIdentity>> historicalIdentities = historicalIdentities(jobId);
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
            List<HistoricalIdentity> aliases = historicalIdentities.getOrDefault(
                    finding.symbol().toUpperCase(Locale.ROOT), List.of());
            items.add(evaluate(finding, identity == null ? null : identity.isin(), aliases, archive, actionTypes));
        }

        int officialMatches = count(items, "OFFICIAL_PRICES_MATCH");
        int officialAdjustedReturnMatches = count(items, "OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES");
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
                jobId, items.size(), archives.size(), officialMatches, officialAdjustedReturnMatches, officialMismatches,
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
        return evaluate(finding, isin, List.of(), archive, actionTypes);
    }

    LargeMoveEvidenceReport.Item evaluate(
            BackfillQualityReport.LargeMoveFinding finding,
            String isin,
            List<HistoricalIdentity> historicalIdentities,
            NseBhavcopyArchive archive,
            List<String> actionTypes
    ) {
        if (!archive.succeeded()) {
            return emptyOfficialItem(finding, isin, archive, actionTypes, archive.status(), "KEEP_OPEN",
                    archive.detail());
        }

        Match match = findOfficialRecord(
                archive.records(), finding.symbol(), isin, historicalIdentities, finding.tradingDate());
        if (match == null) {
            return emptyOfficialItem(
                    finding, isin, archive, actionTypes, "OFFICIAL_INSTRUMENT_NOT_FOUND", "KEEP_OPEN",
                    "The official archive was available, but no supported series matched the current symbol or ISIN.");
        }

        NseBhavcopyRecord official = match.record();
        BigDecimal previousDifference = percentDifference(finding.previousClose(), official.previousClose());
        BigDecimal closeDifference = percentDifference(finding.close(), official.close());
        BigDecimal storedReturn = returnPercent(finding.previousClose(), finding.close());
        BigDecimal officialReturn = returnPercent(official.previousClose(), official.close());
        BigDecimal returnDifference = absoluteDifference(storedReturn, officialReturn);
        BigDecimal previousScale = ratio(official.previousClose(), finding.previousClose());
        BigDecimal closeScale = ratio(official.close(), finding.close());
        BigDecimal scaleDifference = percentDifference(previousScale, closeScale);
        boolean previousMatches = withinTolerance(previousDifference);
        boolean closeMatches = withinTolerance(closeDifference);
        boolean adjustedReturnMatches = withinAdjustedTolerance(returnDifference, scaleDifference);
        String evidenceStatus = previousMatches && closeMatches ? "OFFICIAL_PRICES_MATCH"
                : adjustedReturnMatches ? "OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES"
                : closeMatches ? "OFFICIAL_PREVIOUS_CLOSE_MISMATCH" : "OFFICIAL_CLOSE_MISMATCH";
        String reviewPath = !actionTypes.isEmpty() ? "REVIEW_CORPORATE_ACTION_TRANSITION"
                : "OFFICIAL_PRICES_MATCH".equals(evidenceStatus)
                ? "REVIEW_VERIFIED_EXCHANGE_MOVE"
                : "OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES".equals(evidenceStatus)
                ? "REVIEW_VERIFIED_ADJUSTED_EXCHANGE_MOVE" : "REVIEW_PROVIDER_ADJUSTMENT";
        String detail = "Official NSE prices were matched by " + match.basis()
                + "; return and scale comparisons are advisory, and the suggested review path writes nothing.";

        return new LargeMoveEvidenceReport.Item(
                finding.symbol(), isin, finding.tradingDate(),
                finding.previousClose(), finding.close(), finding.absoluteMovePercent(), evidenceStatus,
                official.symbol(), match.basis(), official.series(), official.previousClose(), official.open(),
                official.high(), official.low(), official.close(), official.volume(), previousDifference,
                closeDifference, storedReturn, officialReturn, returnDifference, previousScale, closeScale,
                scaleDifference, actionTypes, reviewPath, archive.format(), archive.sourceUrl(), detail);
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
                null, null, null, null, null, null,
                actionTypes, reviewPath, archive.format(), archive.sourceUrl(), detail);
    }

    Match findOfficialRecord(
            List<NseBhavcopyRecord> records,
            String symbol,
            String isin,
            List<HistoricalIdentity> historicalIdentities,
            java.time.LocalDate findingDate
    ) {
        Comparator<NseBhavcopyRecord> priority = Comparator.comparingInt(
                record -> SERIES_PRIORITY.indexOf(record.series()));
        Match currentIsin = matchByIsin(records, isin, priority, "ISIN");
        if (currentIsin != null) {
            return currentIsin;
        }
        Match currentSymbol = records.stream()
                .filter(record -> SERIES_PRIORITY.contains(record.series()))
                .filter(record -> symbol.equalsIgnoreCase(record.symbol()))
                .min(priority)
                .map(record -> new Match(record, "SYMBOL"))
                .orElse(null);
        if (currentSymbol != null) {
            return currentSymbol;
        }
        for (HistoricalIdentity historical : historicalIdentities) {
            if (!historical.appliesOn(findingDate)) {
                continue;
            }
            Match historicalIsin = matchByIsin(records, historical.isin(), priority, "HISTORICAL_ISIN");
            if (historicalIsin != null) {
                return historicalIsin;
            }
            Match historicalSymbol = records.stream()
                    .filter(record -> historical.symbol().equalsIgnoreCase(record.symbol()))
                    .min(priority)
                    .map(record -> new Match(record, "HISTORICAL_SYMBOL"))
                    .orElse(null);
            if (historicalSymbol != null) {
                return historicalSymbol;
            }
        }
        return null;
    }

    private Match matchByIsin(
            List<NseBhavcopyRecord> records,
            String isin,
            Comparator<NseBhavcopyRecord> priority,
            String basis
    ) {
        if (isin == null || isin.isBlank()) {
            return null;
        }
        return records.stream()
                .filter(record -> SERIES_PRIORITY.contains(record.series()))
                .filter(record -> isin.equalsIgnoreCase(record.isin()))
                .min(priority)
                .map(record -> new Match(record, basis))
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

    private Map<String, List<HistoricalIdentity>> historicalIdentities(UUID jobId) {
        Map<String, List<HistoricalIdentity>> result = new HashMap<>();
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
                        ignored -> new ArrayList<>()).add(new HistoricalIdentity(
                                rs.getString("alias_symbol"), rs.getString("alias_isin"),
                                rs.getDate("effective_from").toLocalDate(),
                                rs.getDate("effective_to").toLocalDate())), jobId);
        result.replaceAll((key, value) -> List.copyOf(value));
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

    private boolean withinAdjustedTolerance(BigDecimal returnDifference, BigDecimal scaleDifference) {
        return returnDifference != null && scaleDifference != null
                && returnDifference.compareTo(ADJUSTED_RETURN_TOLERANCE_PERCENTAGE_POINTS) <= 0
                && scaleDifference.compareTo(ADJUSTED_SCALE_TOLERANCE_PERCENT) <= 0;
    }

    private BigDecimal returnPercent(BigDecimal previousClose, BigDecimal close) {
        if (previousClose == null || close == null || previousClose.signum() == 0) {
            return null;
        }
        return close.subtract(previousClose)
                .multiply(new BigDecimal("100"))
                .divide(previousClose.abs(), 4, RoundingMode.HALF_UP);
    }

    private BigDecimal absoluteDifference(BigDecimal left, BigDecimal right) {
        return left == null || right == null ? null : left.subtract(right).abs().setScale(4, RoundingMode.HALF_UP);
    }

    private BigDecimal ratio(BigDecimal numerator, BigDecimal denominator) {
        if (numerator == null || denominator == null || denominator.signum() == 0) {
            return null;
        }
        return numerator.divide(denominator, 8, RoundingMode.HALF_UP);
    }

    private int count(List<LargeMoveEvidenceReport.Item> items, String status) {
        return (int) items.stream().filter(item -> status.equals(item.evidenceStatus())).count();
    }

    private record InstrumentIdentity(String symbol, String isin) {
    }

    record HistoricalIdentity(
            String symbol,
            String isin,
            java.time.LocalDate effectiveFrom,
            java.time.LocalDate effectiveTo
    ) {
        boolean appliesOn(java.time.LocalDate date) {
            return !date.isBefore(effectiveFrom) && !date.isAfter(effectiveTo);
        }
    }

    record Match(NseBhavcopyRecord record, String basis) {
    }

    private record SymbolDate(String symbol, java.time.LocalDate date) {
    }
}
