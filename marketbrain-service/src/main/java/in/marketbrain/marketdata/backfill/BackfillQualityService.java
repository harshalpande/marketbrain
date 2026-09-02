package in.marketbrain.marketdata.backfill;

import in.marketbrain.marketdata.upstox.UpstoxCandle;
import in.marketbrain.marketdata.upstox.UpstoxFetchResult;
import in.marketbrain.marketdata.upstox.UpstoxHistoricalRequest;
import in.marketbrain.marketdata.upstox.UpstoxReadOnlyClient;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

@Service
public class BackfillQualityService {

    static final int SUSPICIOUS_GAP_DAYS = 7;
    static final BigDecimal LARGE_MOVE_PERCENT = new BigDecimal("20.00");
    private static final BigDecimal PROVIDER_MATCH_TOLERANCE_PERCENT = new BigDecimal("0.01");
    private static final int MAXIMUM_FINDINGS_PER_TYPE = 100;
    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final JdbcTemplate jdbcTemplate;
    private final UpstoxReadOnlyClient upstoxClient;
    private final BackfillQualityRules rules;

    public BackfillQualityService(
            JdbcTemplate jdbcTemplate,
            UpstoxReadOnlyClient upstoxClient,
            BackfillQualityRules rules
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.upstoxClient = upstoxClient;
        this.rules = rules;
    }

    public BackfillQualityReport audit(UUID jobId, boolean providerSpotCheck) {
        JobScope job = jobScope(jobId);
        if (!List.of("COMPLETED", "PARTIAL_FAILED").contains(job.status())) {
            throw new IllegalStateException("Quality audit requires a completed or partial-failed backfill job");
        }

        List<InstrumentMetrics> metrics = instrumentMetrics(job);
        List<BackfillQualityReport.InstrumentQuality> instruments = metrics.stream()
                .map(metric -> toInstrumentQuality(job, metric))
                .toList();
        List<BackfillQualityReport.GapFinding> gaps = suspiciousGaps(jobId);
        List<BackfillQualityReport.LargeMoveFinding> moves = largeMoves(jobId);
        List<BackfillQualityReport.ProviderSpotCheck> providerChecks = providerSpotCheck
                ? providerSpotChecks(job, metrics)
                : List.of();

        int blocking = (int) instruments.stream().filter(item -> "BLOCKED".equals(item.status())).count();
        int review = (int) instruments.stream().filter(item -> "REVIEW".equals(item.status())).count();
        int providerMismatches = (int) providerChecks.stream()
                .filter(item -> List.of("PRICE_MISMATCH", "DATE_MISMATCH").contains(item.status()))
                .count();
        int providerFailures = (int) providerChecks.stream()
                .filter(item -> !"MATCHED".equals(item.status()))
                .filter(item -> !List.of("PRICE_MISMATCH", "DATE_MISMATCH").contains(item.status()))
                .count();
        String qualityStatus = rules.overallStatus(
                instruments.size(), blocking, review, providerMismatches, providerFailures);

        return new BackfillQualityReport(
                jobId, job.status(), qualityStatus, job.fromDate(), job.toDate(), instruments.size(),
                instruments.stream().mapToLong(BackfillQualityReport.InstrumentQuality::candleCount).sum(),
                blocking, review,
                instruments.stream().mapToInt(BackfillQualityReport.InstrumentQuality::duplicateRows).sum(),
                instruments.stream().mapToInt(BackfillQualityReport.InstrumentQuality::invalidRows).sum(),
                instruments.stream().mapToInt(BackfillQualityReport.InstrumentQuality::suspiciousGapCount).sum(),
                instruments.stream().mapToInt(BackfillQualityReport.InstrumentQuality::largeMoveCount).sum(),
                providerMismatches, providerFailures, SUSPICIOUS_GAP_DAYS, LARGE_MOVE_PERCENT,
                providerSpotCheck, instruments, gaps, moves, providerChecks,
                "Calendar gaps over seven days and close moves over twenty percent are review candidates, "
                        + "not automatic proof of missing data or a corporate action."
        );
    }

    private JobScope jobScope(UUID jobId) {
        List<JobScope> jobs = jdbcTemplate.query("""
                SELECT id, status, requested_from, requested_to
                FROM historical_backfill_job
                WHERE id = ?
                """, (rs, row) -> new JobScope(
                rs.getObject("id", UUID.class), rs.getString("status"), rs.getDate("requested_from").toLocalDate(),
                rs.getDate("requested_to").toLocalDate()), jobId);
        if (jobs.isEmpty()) {
            throw new IllegalArgumentException("Backfill job was not found");
        }
        return jobs.getFirst();
    }

    private List<InstrumentMetrics> instrumentMetrics(JobScope job) {
        return jdbcTemplate.query("""
                WITH job_instruments AS (
                    SELECT DISTINCT instrument_id, provider_instrument_key, source_symbol
                    FROM historical_backfill_chunk
                    WHERE job_id = ?
                ), daily AS (
                    SELECT ji.instrument_id, ji.provider_instrument_key, ji.source_symbol,
                           candle.opened_at,
                           (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                           candle.open_price, candle.high_price, candle.low_price,
                           candle.close_price, candle.volume
                    FROM job_instruments ji
                    JOIN market_candle candle ON candle.instrument_id = ji.instrument_id
                    JOIN market_data_source source ON source.id = candle.source_id AND source.code = 'UPSTOX'
                    WHERE candle.interval_code = 'days:1'
                      AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN ? AND ?
                ), sequenced AS (
                    SELECT daily.*,
                           LAG(trading_date) OVER (PARTITION BY instrument_id ORDER BY trading_date) AS previous_date,
                           LAG(close_price) OVER (PARTITION BY instrument_id ORDER BY trading_date) AS previous_close
                    FROM daily
                )
                SELECT ji.instrument_id, ji.provider_instrument_key, ji.source_symbol,
                       MIN(seq.trading_date) AS first_date,
                       MAX(seq.trading_date) AS last_date,
                       COUNT(seq.opened_at) AS candle_count,
                       COALESCE(MAX(seq.trading_date - seq.previous_date), 0) AS longest_gap_days,
                       COUNT(seq.opened_at) FILTER (
                           WHERE seq.previous_date IS NOT NULL
                             AND seq.trading_date - seq.previous_date > ?
                       ) AS suspicious_gap_count,
                       COUNT(seq.opened_at) FILTER (
                           WHERE seq.previous_close > 0
                             AND ABS((seq.close_price - seq.previous_close) * 100.0 / seq.previous_close) > ?
                       ) AS large_move_count,
                       COALESCE(MAX(
                           CASE WHEN seq.previous_close > 0
                                THEN ABS((seq.close_price - seq.previous_close) * 100.0 / seq.previous_close)
                           END
                       ), 0) AS maximum_move_percent,
                       COUNT(seq.opened_at) - COUNT(DISTINCT seq.trading_date) AS duplicate_rows,
                       COUNT(seq.opened_at) FILTER (
                           WHERE seq.open_price <= 0 OR seq.high_price <= 0 OR seq.low_price <= 0
                              OR seq.close_price <= 0 OR seq.volume < 0
                              OR seq.low_price > seq.open_price OR seq.low_price > seq.close_price
                              OR seq.high_price < seq.open_price OR seq.high_price < seq.close_price
                       ) AS invalid_rows
                FROM job_instruments ji
                LEFT JOIN sequenced seq ON seq.instrument_id = ji.instrument_id
                GROUP BY ji.instrument_id, ji.provider_instrument_key, ji.source_symbol
                ORDER BY ji.source_symbol
                """, (rs, row) -> new InstrumentMetrics(
                rs.getLong("instrument_id"), rs.getString("provider_instrument_key"),
                rs.getString("source_symbol"), localDateOrNull(rs.getDate("first_date")),
                localDateOrNull(rs.getDate("last_date")), rs.getLong("candle_count"),
                rs.getInt("longest_gap_days"), rs.getInt("suspicious_gap_count"),
                rs.getInt("large_move_count"), scaled(rs.getBigDecimal("maximum_move_percent")),
                rs.getInt("duplicate_rows"), rs.getInt("invalid_rows")),
                job.id(), Date.valueOf(job.fromDate()), Date.valueOf(job.toDate()),
                SUSPICIOUS_GAP_DAYS, LARGE_MOVE_PERCENT);
    }

    private List<BackfillQualityReport.GapFinding> suspiciousGaps(UUID jobId) {
        return jdbcTemplate.query("""
                WITH job_instruments AS (
                    SELECT DISTINCT instrument_id, source_symbol
                    FROM historical_backfill_chunk WHERE job_id = ?
                ), dates AS (
                    SELECT ji.source_symbol,
                           (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date
                    FROM job_instruments ji
                    JOIN market_candle candle ON candle.instrument_id = ji.instrument_id
                    JOIN market_data_source source ON source.id = candle.source_id AND source.code = 'UPSTOX'
                    JOIN historical_backfill_job job ON job.id = ?
                    WHERE candle.interval_code = 'days:1'
                      AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                          BETWEEN job.requested_from AND job.requested_to
                ), sequenced AS (
                    SELECT source_symbol, trading_date,
                           LAG(trading_date) OVER (PARTITION BY source_symbol ORDER BY trading_date) AS previous_date
                    FROM dates
                )
                SELECT source_symbol, previous_date, trading_date,
                       trading_date - previous_date AS gap_days
                FROM sequenced
                WHERE previous_date IS NOT NULL AND trading_date - previous_date > ?
                ORDER BY gap_days DESC, source_symbol, trading_date
                LIMIT ?
                """, (rs, row) -> new BackfillQualityReport.GapFinding(
                rs.getString("source_symbol"), rs.getDate("previous_date").toLocalDate(),
                rs.getDate("trading_date").toLocalDate(), rs.getInt("gap_days")),
                jobId, jobId, SUSPICIOUS_GAP_DAYS, MAXIMUM_FINDINGS_PER_TYPE);
    }

    private List<BackfillQualityReport.LargeMoveFinding> largeMoves(UUID jobId) {
        return jdbcTemplate.query("""
                WITH job_instruments AS (
                    SELECT DISTINCT instrument_id, source_symbol
                    FROM historical_backfill_chunk WHERE job_id = ?
                ), prices AS (
                    SELECT ji.source_symbol,
                           (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                           candle.close_price,
                           LAG(candle.close_price) OVER (
                               PARTITION BY ji.instrument_id ORDER BY candle.opened_at
                           ) AS previous_close
                    FROM job_instruments ji
                    JOIN market_candle candle ON candle.instrument_id = ji.instrument_id
                    JOIN market_data_source source ON source.id = candle.source_id AND source.code = 'UPSTOX'
                    JOIN historical_backfill_job job ON job.id = ?
                    WHERE candle.interval_code = 'days:1'
                      AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                          BETWEEN job.requested_from AND job.requested_to
                )
                SELECT source_symbol, trading_date, previous_close, close_price,
                       ABS((close_price - previous_close) * 100.0 / previous_close) AS move_percent
                FROM prices
                WHERE previous_close > 0
                  AND ABS((close_price - previous_close) * 100.0 / previous_close) > ?
                ORDER BY move_percent DESC, source_symbol, trading_date
                LIMIT ?
                """, (rs, row) -> new BackfillQualityReport.LargeMoveFinding(
                rs.getString("source_symbol"), rs.getDate("trading_date").toLocalDate(),
                rs.getBigDecimal("previous_close"), rs.getBigDecimal("close_price"),
                scaled(rs.getBigDecimal("move_percent"))),
                jobId, jobId, LARGE_MOVE_PERCENT, MAXIMUM_FINDINGS_PER_TYPE);
    }

    private List<BackfillQualityReport.ProviderSpotCheck> providerSpotChecks(
            JobScope job,
            List<InstrumentMetrics> metrics
    ) {
        List<BackfillQualityReport.ProviderSpotCheck> checks = new ArrayList<>();
        for (InstrumentMetrics metric : metrics) {
            UpstoxFetchResult<List<UpstoxCandle>> fetch = upstoxClient.fetchHistoricalCandles(
                    new UpstoxHistoricalRequest(metric.providerInstrumentKey(), "days", 1,
                            job.toDate().minusDays(14), job.toDate()));
            if (!fetch.succeeded()) {
                checks.add(new BackfillQualityReport.ProviderSpotCheck(
                        metric.symbol(), fetch.status(), null, null, null, null));
                continue;
            }
            UpstoxCandle providerCandle = fetch.data().stream()
                    .filter(candle -> candle.openedAt() != null && candle.close() != null)
                    .filter(candle -> !candle.openedAt().atZone(INDIA).toLocalDate().isAfter(job.toDate()))
                    .max(Comparator.comparing(UpstoxCandle::openedAt))
                    .orElse(null);
            StoredClose stored = latestStoredClose(metric.instrumentId(), job.toDate());
            if (providerCandle == null || stored == null) {
                checks.add(new BackfillQualityReport.ProviderSpotCheck(
                        metric.symbol(), "NO_COMPARABLE_DATA", null,
                        stored == null ? null : stored.close(),
                        providerCandle == null ? null : providerCandle.close(), null));
                continue;
            }
            LocalDate providerDate = providerCandle.openedAt().atZone(INDIA).toLocalDate();
            BigDecimal difference = percentDifference(stored.close(), providerCandle.close());
            String status = !stored.date().equals(providerDate)
                    ? "DATE_MISMATCH"
                    : difference.compareTo(PROVIDER_MATCH_TOLERANCE_PERCENT) <= 0
                    ? "MATCHED" : "PRICE_MISMATCH";
            checks.add(new BackfillQualityReport.ProviderSpotCheck(
                    metric.symbol(), status, providerDate, stored.close(), providerCandle.close(), difference));
        }
        return List.copyOf(checks);
    }

    private StoredClose latestStoredClose(long instrumentId, LocalDate toDate) {
        List<StoredClose> closes = jdbcTemplate.query("""
                SELECT (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                       candle.close_price
                FROM market_candle candle
                JOIN market_data_source source ON source.id = candle.source_id AND source.code = 'UPSTOX'
                WHERE candle.instrument_id = ? AND candle.interval_code = 'days:1'
                  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date <= ?
                ORDER BY candle.opened_at DESC
                LIMIT 1
                """, (rs, row) -> new StoredClose(
                rs.getDate("trading_date").toLocalDate(), rs.getBigDecimal("close_price")),
                instrumentId, Date.valueOf(toDate));
        return closes.isEmpty() ? null : closes.getFirst();
    }

    private BackfillQualityReport.InstrumentQuality toInstrumentQuality(JobScope job, InstrumentMetrics metric) {
        int leadingGap = boundaryGap(job.fromDate(), metric.firstDate());
        int trailingGap = boundaryGap(metric.lastDate(), job.toDate());
        String status = rules.instrumentStatus(
                metric.candleCount(), metric.duplicateRows(), metric.invalidRows(), leadingGap, trailingGap,
                metric.suspiciousGapCount(), metric.largeMoveCount(), SUSPICIOUS_GAP_DAYS);
        return new BackfillQualityReport.InstrumentQuality(
                metric.symbol(), metric.firstDate(), metric.lastDate(), metric.candleCount(),
                leadingGap, trailingGap, metric.longestGapDays(), metric.suspiciousGapCount(),
                metric.largeMoveCount(), metric.maximumMovePercent(), metric.duplicateRows(),
                metric.invalidRows(), status);
    }

    private int boundaryGap(LocalDate first, LocalDate second) {
        if (first == null || second == null) {
            return 0;
        }
        return Math.max(0, Math.toIntExact(ChronoUnit.DAYS.between(first, second)));
    }

    private BigDecimal percentDifference(BigDecimal stored, BigDecimal provider) {
        if (stored == null || provider == null || provider.signum() == 0) {
            return null;
        }
        return stored.subtract(provider).abs()
                .multiply(new BigDecimal("100"))
                .divide(provider.abs(), 4, RoundingMode.HALF_UP);
    }

    private BigDecimal scaled(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value.setScale(4, RoundingMode.HALF_UP);
    }

    private LocalDate localDateOrNull(Date value) {
        return value == null ? null : value.toLocalDate();
    }

    private record JobScope(UUID id, String status, LocalDate fromDate, LocalDate toDate) {
    }

    private record InstrumentMetrics(
            long instrumentId,
            String providerInstrumentKey,
            String symbol,
            LocalDate firstDate,
            LocalDate lastDate,
            long candleCount,
            int longestGapDays,
            int suspiciousGapCount,
            int largeMoveCount,
            BigDecimal maximumMovePercent,
            int duplicateRows,
            int invalidRows
    ) {
    }

    private record StoredClose(LocalDate date, BigDecimal close) {
    }
}
