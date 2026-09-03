package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import in.marketbrain.marketdata.upstox.ConflictingCandleDataException;
import in.marketbrain.marketdata.upstox.UpstoxHistoricalRequest;
import in.marketbrain.marketdata.upstox.UpstoxImportResult;
import in.marketbrain.marketdata.upstox.UpstoxMarketDataService;
import in.marketbrain.notification.SystemNotificationGateway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Component
public class HistoricalBackfillWorker {

    private static final Logger LOGGER = LoggerFactory.getLogger(HistoricalBackfillWorker.class);

    private final HistoricalBackfillProperties properties;
    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;
    private final UpstoxMarketDataService marketDataService;
    private final BackfillConnectivityPolicy connectivityPolicy;
    private final List<SystemNotificationGateway> notificationGateways;

    public HistoricalBackfillWorker(
            HistoricalBackfillProperties properties,
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate,
            UpstoxMarketDataService marketDataService,
            BackfillConnectivityPolicy connectivityPolicy,
            List<SystemNotificationGateway> notificationGateways
    ) {
        this.properties = properties;
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
        this.marketDataService = marketDataService;
        this.connectivityPolicy = connectivityPolicy;
        this.notificationGateways = notificationGateways;
    }

    @Scheduled(fixedDelayString = "${marketbrain.backfill.worker-delay-millis:1500}")
    public void processNextChunk() {
        if (!properties.workerEnabled()) {
            return;
        }
        recoverAbandonedChunks();
        resumeConnectivityJobsWhenDue();
        BackfillChunk chunk = claimNextChunk();
        if (chunk == null) {
            finalizeFinishedJobs();
            return;
        }

        try {
            UpstoxImportResult result = marketDataService.importHistoricalCandles(new UpstoxHistoricalRequest(
                    chunk.providerInstrumentKey(), "days", 1, chunk.fromDate(), chunk.toDate()));
            if ("SUCCESS".equals(result.status())) {
                ConnectivityRecovery recovery = complete(
                        chunk, result.accepted(), result.rejected(), result.normalizedDuplicates(),
                        result.normalizedDuplicateDates());
                notifyRecoveryIfNeeded(recovery);
            } else if (connectivityPolicy.isTransientInfrastructureFailure(result.status())) {
                ConnectivityWait wait = waitForConnectivity(chunk, result.status());
                notifyConnectivityWaitIfNeeded(wait);
            } else {
                failOrRetry(chunk, result.status());
            }
        } catch (ConflictingCandleDataException conflict) {
            failOrRetry(chunk, "CONFLICTING_CANDLE_DATA");
        } catch (RuntimeException unexpected) {
            failOrRetry(chunk, "WORKER_RUNTIME_FAILURE");
        }
        finalizeFinishedJobs();
    }

    private BackfillChunk claimNextChunk() {
        return transactionTemplate.execute(status -> {
            List<BackfillChunk> candidates = jdbcTemplate.query("""
                    SELECT chunk.id, chunk.job_id, chunk.provider_instrument_key,
                           chunk.from_date, chunk.to_date, chunk.attempts,
                           job.connectivity_failure_count,
                           job.connectivity_notice_sent_at IS NOT NULL AS connectivity_notice_sent
                    FROM historical_backfill_chunk chunk
                    JOIN historical_backfill_job job ON job.id = chunk.job_id
                    WHERE job.status = 'RUNNING'
                      AND (chunk.status = 'PENDING'
                           OR (chunk.status = 'RETRY' AND chunk.next_attempt_at <= CURRENT_TIMESTAMP))
                    ORDER BY chunk.id
                    FOR UPDATE OF chunk SKIP LOCKED
                    LIMIT 1
                    """, (rs, row) -> new BackfillChunk(
                    rs.getLong("id"), rs.getObject("job_id", UUID.class),
                    rs.getString("provider_instrument_key"),
                    rs.getDate("from_date").toLocalDate(), rs.getDate("to_date").toLocalDate(),
                    rs.getInt("attempts"), rs.getInt("connectivity_failure_count"),
                    rs.getBoolean("connectivity_notice_sent")));
            if (candidates.isEmpty()) {
                return null;
            }
            BackfillChunk candidate = candidates.getFirst();
            jdbcTemplate.update("""
                    UPDATE historical_backfill_chunk
                    SET status = 'RUNNING', attempts = attempts + 1,
                        started_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, candidate.id());
            return new BackfillChunk(candidate.id(), candidate.jobId(), candidate.providerInstrumentKey(),
                    candidate.fromDate(), candidate.toDate(), candidate.attempts() + 1,
                    candidate.connectivityFailureCount(), candidate.connectivityNoticeSent());
        });
    }

    private ConnectivityRecovery complete(
            BackfillChunk chunk,
            int accepted,
            int rejected,
            int normalizedDuplicates,
            List<LocalDate> normalizedDuplicateDates
    ) {
        return transactionTemplate.execute(status -> {
            List<ConnectivityRecovery> recoveries = jdbcTemplate.query("""
                    SELECT connectivity_wait_started_at,
                           connectivity_notice_sent_at IS NOT NULL AS notice_sent
                    FROM historical_backfill_job
                    WHERE id = ? AND connectivity_wait_started_at IS NOT NULL
                    """, (rs, row) -> new ConnectivityRecovery(
                    chunk.jobId(), rs.getTimestamp("connectivity_wait_started_at").toInstant(),
                    rs.getBoolean("notice_sent")), chunk.jobId());
            jdbcTemplate.update("""
                    UPDATE historical_backfill_chunk
                    SET status = 'COMPLETED', accepted_rows = ?, rejected_rows = ?,
                        last_error_code = NULL, next_attempt_at = NULL,
                        completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, accepted, rejected, chunk.id());
            if (rejected > 0) {
                jdbcTemplate.update("""
                        INSERT INTO market_data_quality_issue
                            (job_id, chunk_id, instrument_id, issue_code, severity, affected_rows)
                        SELECT chunk.job_id, chunk.id, chunk.instrument_id,
                               'REJECTED_CANDLE_ROWS', 'WARNING', ?
                        FROM historical_backfill_chunk chunk WHERE chunk.id = ?
                        """, rejected, chunk.id());
            }
            if (normalizedDuplicates > 0) {
                jdbcTemplate.update("""
                        INSERT INTO market_data_quality_issue
                            (job_id, chunk_id, instrument_id, issue_code, severity, affected_rows, details)
                        SELECT chunk.job_id, chunk.id, chunk.instrument_id,
                               'PROVIDER_DUPLICATE_NORMALIZED', 'INFO', ?, ?
                        FROM historical_backfill_chunk chunk WHERE chunk.id = ?
                        ON CONFLICT (chunk_id, issue_code) WHERE chunk_id IS NOT NULL AND resolved_at IS NULL
                        DO UPDATE SET affected_rows = EXCLUDED.affected_rows,
                                      details = EXCLUDED.details,
                                      detected_at = CURRENT_TIMESTAMP
                        """, normalizedDuplicates,
                        "Normalized near-identical provider daily candles for trading date(s): "
                                + normalizedDuplicateDates,
                        chunk.id());
            }
            jdbcTemplate.update("""
                    UPDATE historical_backfill_job
                    SET connectivity_failure_count = 0,
                        connectivity_retry_at = NULL,
                        connectivity_wait_started_at = NULL,
                        connectivity_notice_sent_at = NULL,
                        last_connectivity_error_code = NULL,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, chunk.jobId());
            return recoveries.isEmpty() ? null : recoveries.getFirst();
        });
    }

    private ConnectivityWait waitForConnectivity(BackfillChunk chunk, String errorCode) {
        int failureCount = chunk.connectivityFailureCount() + 1;
        Instant retryAt = Instant.now().plus(connectivityPolicy.retryDelay(failureCount));
        transactionTemplate.executeWithoutResult(status -> {
            jdbcTemplate.update("""
                    UPDATE historical_backfill_chunk
                    SET status = 'RETRY', attempts = GREATEST(attempts - 1, 0),
                        last_error_code = ?, next_attempt_at = ?, completed_at = NULL,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, safeCode(errorCode), Timestamp.from(retryAt), chunk.id());
            jdbcTemplate.update("""
                    UPDATE historical_backfill_job
                    SET status = 'WAITING_FOR_CONNECTIVITY',
                        connectivity_failure_count = ?,
                        connectivity_retry_at = ?,
                        connectivity_wait_started_at = COALESCE(connectivity_wait_started_at, CURRENT_TIMESTAMP),
                        last_connectivity_error_code = ?,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, failureCount, Timestamp.from(retryAt), safeCode(errorCode), chunk.jobId());
        });
        return new ConnectivityWait(chunk.jobId(), retryAt, failureCount, chunk.connectivityNoticeSent());
    }

    private void resumeConnectivityJobsWhenDue() {
        jdbcTemplate.update("""
                UPDATE historical_backfill_job
                SET status = 'RUNNING', connectivity_retry_at = NULL,
                    updated_at = CURRENT_TIMESTAMP
                WHERE status = 'WAITING_FOR_CONNECTIVITY'
                  AND connectivity_retry_at <= CURRENT_TIMESTAMP
                """);
    }

    private void notifyConnectivityWaitIfNeeded(ConnectivityWait wait) {
        if (wait.noticeAlreadySent() || notificationGateways.isEmpty()) {
            return;
        }
        String message = """
                [SYSTEM NOTE] PAPER MODE
                Historical data backfill is waiting for internet or Upstox availability.
                Automatic retry: %s
                No trading action is required.
                """.formatted(wait.retryAt()).strip();
        if (sendSystemNote(message)) {
            jdbcTemplate.update("""
                    UPDATE historical_backfill_job
                    SET connectivity_notice_sent_at = CURRENT_TIMESTAMP,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ? AND connectivity_notice_sent_at IS NULL
                    """, wait.jobId());
        }
    }

    private void notifyRecoveryIfNeeded(ConnectivityRecovery recovery) {
        if (recovery == null || recovery.noticeAlreadySent() || notificationGateways.isEmpty()) {
            return;
        }
        String message = """
                [SYSTEM NOTE] PAPER MODE
                Historical data backfill automatically resumed after connectivity returned.
                No trading action is required.
                """.strip();
        sendSystemNote(message);
    }

    private boolean sendSystemNote(String message) {
        try {
            notificationGateways.getFirst().sendNote(message);
            return true;
        } catch (RuntimeException exception) {
            LOGGER.warn("Backfill system NOTE could not be delivered; processing remains safe.");
            return false;
        }
    }

    private void failOrRetry(BackfillChunk chunk, String errorCode) {
        boolean retry = chunk.attempts() < properties.maximumAttempts();
        jdbcTemplate.update("""
                UPDATE historical_backfill_chunk
                SET status = ?, last_error_code = ?,
                    next_attempt_at = CASE WHEN ? THEN CURRENT_TIMESTAMP + INTERVAL '60 seconds' ELSE NULL END,
                    completed_at = CASE WHEN ? THEN NULL ELSE CURRENT_TIMESTAMP END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """, retry ? "RETRY" : "FAILED", safeCode(errorCode), retry, retry, chunk.id());
    }

    private void recoverAbandonedChunks() {
        jdbcTemplate.update("""
                UPDATE historical_backfill_chunk chunk
                SET status = CASE WHEN attempts < ? THEN 'RETRY' ELSE 'FAILED' END,
                    last_error_code = 'ABANDONED_AFTER_RESTART',
                    next_attempt_at = CASE WHEN attempts < ? THEN CURRENT_TIMESTAMP ELSE NULL END,
                    completed_at = CASE WHEN attempts < ? THEN NULL ELSE CURRENT_TIMESTAMP END,
                    updated_at = CURRENT_TIMESTAMP
                FROM historical_backfill_job job
                WHERE chunk.job_id = job.id AND job.status = 'RUNNING'
                  AND chunk.status = 'RUNNING'
                  AND chunk.updated_at < CURRENT_TIMESTAMP - INTERVAL '10 minutes'
                """, properties.maximumAttempts(), properties.maximumAttempts(), properties.maximumAttempts());
    }

    private void finalizeFinishedJobs() {
        jdbcTemplate.update("""
                UPDATE historical_backfill_job job
                SET status = CASE
                        WHEN EXISTS (SELECT 1 FROM historical_backfill_chunk c
                                     WHERE c.job_id = job.id AND c.status = 'FAILED')
                            THEN 'PARTIAL_FAILED'
                        ELSE 'COMPLETED'
                    END,
                    completed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP
                WHERE job.status = 'RUNNING'
                  AND NOT EXISTS (
                      SELECT 1 FROM historical_backfill_chunk c
                      WHERE c.job_id = job.id AND c.status IN ('PENDING', 'RUNNING', 'RETRY')
                  )
                """);
    }

    private String safeCode(String value) {
        if (value == null || value.isBlank()) {
            return "UNKNOWN_PROVIDER_FAILURE";
        }
        return value.length() <= 64 ? value : value.substring(0, 64);
    }

    private record BackfillChunk(
            long id,
            UUID jobId,
            String providerInstrumentKey,
            LocalDate fromDate,
            LocalDate toDate,
            int attempts,
            int connectivityFailureCount,
            boolean connectivityNoticeSent
    ) {
    }

    private record ConnectivityWait(
            UUID jobId,
            Instant retryAt,
            int failureCount,
            boolean noticeAlreadySent
    ) {
    }

    private record ConnectivityRecovery(
            UUID jobId,
            Instant waitStartedAt,
            boolean noticeAlreadySent
    ) {
    }
}
