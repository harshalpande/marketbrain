package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

@Service
public class NumericalHistoryCoverageService {
    private static final ZoneId MARKET_ZONE = ZoneId.of("Asia/Kolkata");
    static final int ROW_CAP = 2000;
    static final String RUN_SQL = """
            SELECT as_of, dataset_manifest_hash, instrument_count
            FROM prototype_swing_training_dataset_run WHERE id = ? AND status = 'COMPLETED'
            """;
    // Leading instrument/date predicates use V24's partial daily-complete index.
    // LIMIT sentinel bounds per-instrument records entering aggregation; statement timeout
    // also bounds a poorly performing/missing-index deployment. Never change shared JdbcTemplate settings.
    static final String COVERAGE_SQL = """
            WITH selected AS (
                SELECT id, instrument_id, symbol, classification, detail, effective_as_of
                FROM prototype_swing_training_dataset_item
                WHERE run_id = ? ORDER BY instrument_id LIMIT ? OFFSET ?
            ), exclusions AS MATERIALIZED (
                SELECT DISTINCT e.instrument_id, e.exclusion_from, e.exclusion_to
                FROM market_data_feature_exclusion e JOIN selected s ON s.instrument_id = e.instrument_id
                WHERE e.exclusion_from <= ? AND e.exclusion_to >= ?
            )
            SELECT item.*, coverage.*
            FROM selected item
            CROSS JOIN LATERAL (
                SELECT COUNT(*) AS scanned_rows,
                       COUNT(DISTINCT trading_date) AS observed_dates,
                       COUNT(DISTINCT trading_date) FILTER (WHERE NOT excluded) AS nonexcluded_dates,
                       COUNT(DISTINCT trading_date) FILTER (WHERE excluded) AS excluded_dates,
                       MIN(trading_date) AS first_date, MAX(trading_date) AS last_date,
                       COUNT(*) FILTER (WHERE received_at > ?) AS received_after_cutoff,
                       COUNT(*) FILTER (WHERE received_at IS NULL) AS missing_received_at,
                       COUNT(*) FILTER (WHERE source_code = 'NSE_BHAVCOPY') AS nse_rows,
                       COUNT(*) FILTER (WHERE source_code = 'UPSTOX') AS upstox_rows
                FROM (
                    SELECT (c.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                           c.received_at, source.code AS source_code,
                           EXISTS (SELECT 1 FROM exclusions e
                                   WHERE e.instrument_id = c.instrument_id
                                     AND (c.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                                         BETWEEN e.exclusion_from AND e.exclusion_to) AS excluded
                    FROM market_candle c JOIN market_data_source source ON source.id = c.source_id
                    WHERE c.instrument_id = item.instrument_id AND c.interval_code = 'days:1'
                      AND c.is_complete = TRUE AND source.code IN ('NSE_BHAVCOPY','UPSTOX')
                      AND c.opened_at >= ? AND c.opened_at < ?
                    ORDER BY c.opened_at DESC, c.source_id, c.received_at DESC, c.id DESC
                    LIMIT 2001
                ) bounded
            ) coverage ORDER BY item.instrument_id
            """;
    private final JdbcTemplate jdbc;

    public NumericalHistoryCoverageService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Transactional(readOnly = true, timeout = 30)
    public CoveragePage inspect(UUID runId, int offset, int limit, int lookbackDays) {
        if (runId == null || runId.equals(new UUID(0, 0)) || offset < 0 || offset > 499
                || limit < 1 || limit > 50 || lookbackDays < 252 || lookbackDays > 730) {
            throw new IllegalArgumentException("Explicit run required; offset 0..499, limit 1..50, lookbackDays 252..730.");
        }
        List<Run> runs = jdbc.query(RUN_SQL, statement -> {
            statement.setObject(1, runId); statement.setQueryTimeout(5);
        }, (rs, row) -> new Run(rs.getObject("as_of", LocalDate.class),
                rs.getString("dataset_manifest_hash"), rs.getInt("instrument_count")));
        if (runs.size() != 1) { throw new IllegalArgumentException("Completed dataset run not found."); }
        Run run = runs.getFirst();
        if (run.count() < 1 || run.count() > 500 || offset >= run.count()) {
            throw new IllegalArgumentException("This diagnostic supports 1..500 instruments and an offset within the run.");
        }
        LocalDate from = run.asOf().minusDays(lookbackDays - 1L);
        var cutoff = run.asOf().atTime(LocalTime.of(16, 0)).atZone(MARKET_ZONE).toInstant();
        List<InstrumentCoverage> items = jdbc.query(COVERAGE_SQL, statement -> {
            statement.setObject(1, runId); statement.setInt(2, limit); statement.setInt(3, offset);
            statement.setObject(4, run.asOf()); statement.setObject(5, from);
            statement.setTimestamp(6, Timestamp.from(cutoff));
            statement.setTimestamp(7, Timestamp.from(from.atStartOfDay(MARKET_ZONE).toInstant()));
            statement.setTimestamp(8, Timestamp.from(run.asOf().plusDays(1).atStartOfDay(MARKET_ZONE).toInstant()));
            // Setter runs after JdbcTemplate settings; preserve the tighter per-statement limit.
            statement.setFetchSize(50); statement.setQueryTimeout(15);
        }, (rs, row) -> new InstrumentCoverage(rs.getLong("instrument_id"), rs.getString("symbol"),
                rs.getString("classification"), rs.getString("detail"), rs.getObject("effective_as_of", LocalDate.class),
                rs.getInt("scanned_rows"), rs.getInt("observed_dates"), rs.getInt("nonexcluded_dates"),
                rs.getInt("excluded_dates"), rs.getObject("first_date", LocalDate.class),
                rs.getObject("last_date", LocalDate.class), rs.getInt("received_after_cutoff"),
                rs.getInt("missing_received_at"), rs.getInt("nse_rows"), rs.getInt("upstox_rows"),
                rs.getInt("scanned_rows") > ROW_CAP));
        if (items.size() != Math.min(limit, run.count() - offset)) {
            throw new IllegalStateException("Run metadata/item pagination mismatch; no completeness claim allowed.");
        }
        int next = offset + items.size();
        return new CoveragePage("NUMERICAL_HISTORY_COVERAGE_V1", "REVIEW_REQUIRED", runId,
                run.manifest(), run.asOf(), from, lookbackDays, offset, limit, run.count(),
                next < run.count() ? next : null, items, items.stream().anyMatch(InstrumentCoverage::truncated),
                NumericalDataContract.draft(), false, 0, 0, 0,
                "Retrospective stored daily data in requested window only. Counts collapse dates, not source canonicalization/OHLC validation. "
                        + "Overlapping source rows are not necessarily invalid duplicates. Exclusions are current, not historical vintages. "
                        + "252 nonexcluded dates is a warm-up hint, not recomputed feature eligibility or exchange-session completeness. "
                        + "Received-after-cutoff counts flag ingestion timing, not proof those prices were unknowable then. "
                        + "Pages are separate reads, not an atomic snapshot; candles/exclusions may change between pages. "
                        + "No missing-session, 15-year, source-rights, listing-age or point-in-time certification; no future bars, labels or training.");
    }

    record Run(LocalDate asOf, String manifest, int count) { }
    public record InstrumentCoverage(long instrumentId, String symbol, String persistedClassification,
            String persistedReason, LocalDate effectiveAsOf, int rawRowsScanned, int observedDates,
            int nonexcludedDates, int excludedDates, LocalDate firstObservedDate, LocalDate lastObservedDate,
            int receivedAfterDecisionCutoffRows, int missingReceivedAtRows, int nseRows, int upstoxRows,
            boolean truncated) { }
    public record CoveragePage(String version, String status, UUID datasetRunId, String datasetManifestHash,
            LocalDate asOf, LocalDate windowFrom, int lookbackDays, int offset, int limit, int instrumentCount,
            Integer nextOffset, List<InstrumentCoverage> instruments, boolean partial,
            NumericalDataContract contract, boolean databaseWritesPerformed, int modelCallCount,
            int providerCallCount, int ordersCreated, String limitations) { }
}
