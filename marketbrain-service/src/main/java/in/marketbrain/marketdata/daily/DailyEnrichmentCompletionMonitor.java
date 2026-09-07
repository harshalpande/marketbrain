package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.UUID;

@Component
public class DailyEnrichmentCompletionMonitor {

    private final JdbcTemplate jdbcTemplate;
    private final DailyEnrichmentProperties properties;
    private final DailyEnrichmentNotificationService notificationService;

    public DailyEnrichmentCompletionMonitor(
            JdbcTemplate jdbcTemplate,
            DailyEnrichmentProperties properties,
            DailyEnrichmentNotificationService notificationService
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.properties = properties;
        this.notificationService = notificationService;
    }

    @Scheduled(fixedDelayString = "${marketbrain.daily-enrichment.completion-monitor-delay-millis}")
    public void notifyTerminalRuns() {
        if (!properties.schedulerEnabled()) {
            return;
        }
        for (RunOutcome run : terminalRunsAwaitingNotice()) {
            if (run.clean()) {
                notificationService.sendCompletion(run.targetDate(), run.runId(), completionMessage(run));
            } else if (warningWindowReached()) {
                notificationService.sendWarning(run.targetDate(), run.runId(), warningMessage(run));
            }
        }
    }

    private boolean warningWindowReached() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of(properties.zone()));
        return !now.toLocalTime().isBefore(LocalTime.parse(properties.providerWindowCutoff()));
    }

    private List<RunOutcome> terminalRunsAwaitingNotice() {
        return jdbcTemplate.query("""
                WITH chunk_metrics AS (
                    SELECT job_id,
                           COUNT(DISTINCT instrument_id) AS instruments,
                           COUNT(*) AS total_chunks,
                           COUNT(*) FILTER (WHERE status = 'COMPLETED') AS completed_chunks,
                           COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_chunks,
                           COALESCE(SUM(accepted_rows), 0) AS accepted_rows,
                           COALESCE(SUM(rejected_rows), 0) AS rejected_rows
                    FROM historical_backfill_chunk
                    GROUP BY job_id
                ), target_coverage AS (
                    SELECT job.id AS job_id,
                           COUNT(DISTINCT chunk.instrument_id)
                               - COUNT(DISTINCT candle.instrument_id)
                                   FILTER (WHERE source.code = 'UPSTOX') AS missing_target_instruments
                    FROM historical_backfill_job job
                    JOIN historical_backfill_chunk chunk ON chunk.job_id = job.id
                    LEFT JOIN market_candle candle
                           ON candle.instrument_id = chunk.instrument_id
                          AND candle.interval_code = 'days:1'
                          AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date = job.requested_to
                    LEFT JOIN market_data_source source ON source.id = candle.source_id
                    WHERE job.job_type = 'DAILY'
                    GROUP BY job.id
                )
                SELECT job.id, job.requested_to, job.status,
                       metrics.instruments, metrics.total_chunks, metrics.completed_chunks,
                       metrics.failed_chunks, metrics.accepted_rows, metrics.rejected_rows,
                       coverage.missing_target_instruments
                FROM historical_backfill_job job
                JOIN chunk_metrics metrics ON metrics.job_id = job.id
                JOIN target_coverage coverage ON coverage.job_id = job.id
                WHERE job.job_type = 'DAILY'
                  AND job.status IN ('COMPLETED', 'PARTIAL_FAILED')
                  AND NOT EXISTS (
                      SELECT 1 FROM daily_enrichment_notification notice
                      WHERE notice.target_date = job.requested_to
                        AND notice.delivery_status IN ('SENT', 'SUPPRESSED')
                  )
                ORDER BY job.requested_to, job.created_at
                """, (rs, row) -> new RunOutcome(
                rs.getObject("id", UUID.class), rs.getDate("requested_to").toLocalDate(),
                rs.getString("status"), rs.getInt("instruments"), rs.getInt("total_chunks"),
                rs.getInt("completed_chunks"), rs.getInt("failed_chunks"),
                rs.getLong("accepted_rows"), rs.getLong("rejected_rows"),
                rs.getInt("missing_target_instruments")));
    }

    static String completionMessage(RunOutcome run) {
        return """
                [DAILY DATA COMPLETE] PAPER MODE
                Trading date: %s
                Instruments: %d
                Chunks: %d/%d completed
                Accepted candles: %d
                Rejected rows: %d
                Target-date gaps: %d
                Data collection only; no trading action is required.
                """.formatted(run.targetDate(), run.instruments(), run.completedChunks(),
                run.totalChunks(), run.acceptedRows(), run.rejectedRows(),
                run.missingTargetInstruments()).strip();
    }

    static String warningMessage(RunOutcome run) {
        return """
                [DAILY DATA WARNING] PAPER MODE
                Trading date: %s
                Run status: %s
                Chunks: %d/%d completed; %d failed
                Accepted candles: %d
                Rejected rows: %d
                Target-date gaps: %d
                Review is required; stale or incomplete data remains non-actionable.
                """.formatted(run.targetDate(), run.status(), run.completedChunks(), run.totalChunks(),
                run.failedChunks(), run.acceptedRows(), run.rejectedRows(),
                run.missingTargetInstruments()).strip();
    }

    record RunOutcome(
            UUID runId,
            LocalDate targetDate,
            String status,
            int instruments,
            int totalChunks,
            int completedChunks,
            int failedChunks,
            long acceptedRows,
            long rejectedRows,
            int missingTargetInstruments
    ) {
        boolean clean() {
            return "COMPLETED".equals(status)
                    && totalChunks > 0
                    && completedChunks == totalChunks
                    && failedChunks == 0
                    && rejectedRows == 0
                    && missingTargetInstruments == 0;
        }
    }
}
