package in.marketbrain.feature;

import in.marketbrain.configuration.DailyFeatureSnapshotProperties;
import in.marketbrain.marketdata.daily.DailyEnrichmentNotificationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.Date;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
public class DailyFeatureSnapshotAutomationService {

    private static final Logger LOGGER = LoggerFactory.getLogger(DailyFeatureSnapshotAutomationService.class);
    private static final String AUTOMATION_REVIEWER = "SYSTEM_DAILY_AUTOMATION";

    private final JdbcTemplate jdbcTemplate;
    private final DailyFeatureSnapshotProperties properties;
    private final DailyFeatureAutomationPreviewService previewService;
    private final FeatureSnapshotService snapshotService;
    private final DailyEnrichmentNotificationService notificationService;

    public DailyFeatureSnapshotAutomationService(
            JdbcTemplate jdbcTemplate,
            DailyFeatureSnapshotProperties properties,
            DailyFeatureAutomationPreviewService previewService,
            FeatureSnapshotService snapshotService,
            DailyEnrichmentNotificationService notificationService
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.properties = properties;
        this.previewService = previewService;
        this.snapshotService = snapshotService;
        this.notificationService = notificationService;
    }

    public void runOnce() {
        if (!properties.enabled()) {
            return;
        }
        seedCandidates();
        expireExhaustedClaims();
        List<ClaimedWork> claims = claimNext();
        if (!claims.isEmpty()) {
            process(claims.getFirst());
        }
        notifyTerminalOutcomes();
    }

    public DailyFeatureSnapshotAutomationStatus status(LocalDate targetDate) {
        if (targetDate == null) {
            throw new IllegalArgumentException("A target date is required.");
        }
        List<AutomationRow> rows = jdbcTemplate.query("""
                SELECT automation.status, automation.attempts, automation.daily_run_id,
                       automation.feature_snapshot_run_id, automation.feature_manifest_hash,
                       automation.eligible_count, automation.withheld_count, automation.last_error_code,
                       notice.delivery_status AS notification_status
                FROM daily_feature_snapshot_automation automation
                LEFT JOIN daily_enrichment_notification notice
                  ON notice.target_date = automation.target_date
                 AND notice.notice_kind = CASE
                     WHEN automation.status = 'COMPLETED' THEN 'FEATURE_COMPLETION'
                     WHEN automation.status IN ('REVIEW_REQUIRED', 'FAILED') THEN 'FEATURE_WARNING'
                     ELSE NULL
                 END
                WHERE automation.target_date = ?
                """, (resultSet, row) -> new AutomationRow(
                        resultSet.getString("status"),
                        resultSet.getInt("attempts"),
                        resultSet.getObject("daily_run_id", UUID.class),
                        resultSet.getObject("feature_snapshot_run_id", UUID.class),
                        resultSet.getString("feature_manifest_hash"),
                        resultSet.getObject("eligible_count", Integer.class),
                        resultSet.getObject("withheld_count", Integer.class),
                        resultSet.getString("last_error_code"),
                        resultSet.getString("notification_status")),
                Date.valueOf(targetDate));
        if (rows.isEmpty()) {
            return new DailyFeatureSnapshotAutomationStatus(
                    properties.enabled(), properties.activationDate(), targetDate, "NOT_SCHEDULED", 0,
                    null, null, null, null, null, null, null,
                    targetDate.isBefore(properties.activationDate())
                            ? "The target date predates automatic feature activation."
                            : "No completed daily run has been claimed for this target date."
            );
        }
        AutomationRow row = rows.getFirst();
        return new DailyFeatureSnapshotAutomationStatus(
                properties.enabled(), properties.activationDate(), targetDate, row.status(), row.attempts(),
                row.dailyRunId(), row.featureSnapshotRunId(), row.manifestHash(), row.eligibleCount(),
                row.withheldCount(), row.lastErrorCode(), row.notificationStatus(),
                "Durable automatic feature-snapshot checkpoint."
        );
    }

    private void seedCandidates() {
        jdbcTemplate.update("""
                INSERT INTO daily_feature_snapshot_automation
                    (target_date, daily_run_id, status)
                SELECT job.requested_to, job.id, 'PENDING'
                FROM historical_backfill_job job
                WHERE job.job_type = 'DAILY'
                  AND job.status = 'COMPLETED'
                  AND job.requested_to >= ?
                ON CONFLICT DO NOTHING
                """, Date.valueOf(properties.activationDate()));
    }

    private List<ClaimedWork> claimNext() {
        return jdbcTemplate.query("""
                UPDATE daily_feature_snapshot_automation
                SET status = 'RUNNING', attempts = attempts + 1,
                    started_at = COALESCE(started_at, CURRENT_TIMESTAMP),
                    last_error_code = NULL, updated_at = CURRENT_TIMESTAMP
                WHERE id = (
                    SELECT id
                    FROM daily_feature_snapshot_automation
                    WHERE attempts < ?
                      AND (
                          status = 'PENDING'
                          OR (status = 'RETRY'
                              AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '5 minutes')
                          OR (status = 'RUNNING'
                              AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '60 minutes')
                      )
                    ORDER BY target_date
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED
                )
                RETURNING id, target_date, daily_run_id, attempts
                """, (resultSet, row) -> new ClaimedWork(
                        resultSet.getLong("id"),
                        resultSet.getObject("target_date", LocalDate.class),
                        resultSet.getObject("daily_run_id", UUID.class),
                        resultSet.getInt("attempts")),
                properties.maximumAttempts());
    }

    private void expireExhaustedClaims() {
        jdbcTemplate.update("""
                UPDATE daily_feature_snapshot_automation
                SET status = 'FAILED', last_error_code = 'STALE_EXHAUSTED_CLAIM',
                    completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE status = 'RUNNING'
                  AND attempts >= ?
                  AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '60 minutes'
                """, properties.maximumAttempts());
    }

    private void process(ClaimedWork work) {
        try {
            DailyFeatureAutomationPreview preview = previewService.preview(work.targetDate());
            if (!"READY".equals(preview.status())) {
                markReviewRequired(work, preview);
                return;
            }
            if (!work.dailyRunId().equals(preview.dailyRunId())) {
                markReviewRequired(work, preview, "DAILY_RUN_ALIGNMENT");
                return;
            }
            UUID featureRunId;
            if ("ALREADY_PERSISTED".equals(preview.persistenceAction())) {
                featureRunId = preview.existingFeatureSnapshotRunId();
            } else if ("READY_TO_PERSIST".equals(preview.persistenceAction())) {
                FeatureSnapshotSummary persisted = snapshotService.persist(new FeatureSnapshotRequest(
                        work.targetDate(), preview.featureManifestHash(), AUTOMATION_REVIEWER));
                featureRunId = persisted.runId();
            } else {
                markReviewRequired(work, preview);
                return;
            }
            FeatureSnapshotQuality quality = snapshotService.quality(
                    featureRunId, preview.featureManifestHash());
            if (!"ELIGIBLE".equals(quality.status())
                    || !featureRunId.equals(quality.runId())
                    || !work.targetDate().equals(quality.requestedAsOf())
                    || !preview.featureSetVersion().equals(quality.featureSetVersion())
                    || !preview.featureManifestHash().equals(quality.sourceManifestHash())
                    || quality.instrumentCount() != preview.featureInstrumentCount()
                    || quality.persistedFeatureCount() != preview.eligibleCount()
                    || quality.withheldCount()
                    != preview.featureInstrumentCount() - preview.eligibleCount()
                    || !quality.manifestMatches()
                    || quality.databaseWritesPerformed()) {
                throw new IllegalStateException("Persisted feature quality verification failed");
            }
            int updated = jdbcTemplate.update("""
                    UPDATE daily_feature_snapshot_automation
                    SET status = 'COMPLETED', feature_snapshot_run_id = ?,
                        feature_manifest_hash = ?, eligible_count = ?, withheld_count = ?,
                        completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP,
                        last_error_code = NULL
                    WHERE id = ? AND status = 'RUNNING'
                    """, featureRunId, preview.featureManifestHash(), preview.eligibleCount(),
                    preview.featureInstrumentCount() - preview.eligibleCount(), work.id());
            if (updated != 1) {
                throw new IllegalStateException("Automatic feature checkpoint changed while completing");
            }
            LOGGER.info("Daily feature snapshot automation completed for {} with run {}.",
                    work.targetDate(), featureRunId);
        } catch (RuntimeException exception) {
            recordFailure(work, exception);
        }
    }

    private void markReviewRequired(ClaimedWork work, DailyFeatureAutomationPreview preview) {
        String reason = preview.failedCheckpoints().isEmpty()
                ? "AUTOMATION_GATES"
                : String.join("_", preview.failedCheckpoints());
        markReviewRequired(work, preview, reason);
    }

    private void markReviewRequired(
            ClaimedWork work,
            DailyFeatureAutomationPreview preview,
            String reason
    ) {
        Integer eligibleCount = preview.featureInstrumentCount() == 500
                ? preview.eligibleCount() : null;
        Integer withheldCount = preview.featureInstrumentCount() == 500
                ? preview.featureInstrumentCount() - preview.eligibleCount() : null;
        jdbcTemplate.update("""
                UPDATE daily_feature_snapshot_automation
                SET status = 'REVIEW_REQUIRED', feature_manifest_hash = ?,
                    eligible_count = ?, withheld_count = ?, last_error_code = ?,
                    completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = 'RUNNING'
                """, preview.featureManifestHash(), eligibleCount,
                withheldCount, reason, work.id());
        LOGGER.warn("Daily feature snapshot automation requires review for {}: {}.",
                work.targetDate(), reason);
    }

    private void recordFailure(ClaimedWork work, RuntimeException exception) {
        String nextStatus = work.attempts() >= properties.maximumAttempts() ? "FAILED" : "RETRY";
        String errorCode = exception.getClass().getSimpleName();
        jdbcTemplate.update("""
                UPDATE daily_feature_snapshot_automation
                SET status = ?, last_error_code = ?, completed_at = CASE
                        WHEN ? = 'FAILED' THEN CURRENT_TIMESTAMP ELSE NULL END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = 'RUNNING'
                """, nextStatus, errorCode, nextStatus, work.id());
        LOGGER.warn("Daily feature snapshot automation attempt {} for {} ended as {} ({}).",
                work.attempts(), work.targetDate(), nextStatus, errorCode);
    }

    private void notifyTerminalOutcomes() {
        List<NotificationOutcome> outcomes = jdbcTemplate.query("""
                SELECT automation.target_date, automation.daily_run_id,
                       automation.feature_snapshot_run_id, automation.status,
                       automation.feature_manifest_hash, automation.eligible_count,
                       automation.withheld_count, automation.last_error_code
                FROM daily_feature_snapshot_automation automation
                WHERE automation.status IN ('COMPLETED', 'REVIEW_REQUIRED', 'FAILED')
                  AND NOT EXISTS (
                      SELECT 1
                      FROM daily_enrichment_notification notice
                      WHERE notice.target_date = automation.target_date
                        AND notice.notice_kind = CASE
                            WHEN automation.status = 'COMPLETED' THEN 'FEATURE_COMPLETION'
                            ELSE 'FEATURE_WARNING'
                        END
                        AND notice.delivery_status IN ('SENT', 'SUPPRESSED')
                  )
                ORDER BY automation.target_date
                """, (resultSet, row) -> new NotificationOutcome(
                        resultSet.getObject("target_date", LocalDate.class),
                        resultSet.getObject("daily_run_id", UUID.class),
                        resultSet.getObject("feature_snapshot_run_id", UUID.class),
                        resultSet.getString("status"),
                        resultSet.getString("feature_manifest_hash"),
                        resultSet.getObject("eligible_count", Integer.class),
                        resultSet.getObject("withheld_count", Integer.class),
                        resultSet.getString("last_error_code")));
        for (NotificationOutcome outcome : outcomes) {
            if ("COMPLETED".equals(outcome.status())) {
                notificationService.sendFeatureCompletion(
                        outcome.targetDate(), outcome.dailyRunId(), completionMessage(outcome));
            } else {
                notificationService.sendFeatureWarning(
                        outcome.targetDate(), outcome.dailyRunId(), warningMessage(outcome));
            }
        }
    }

    static String completionMessage(NotificationOutcome outcome) {
        return """
                [DAILY FEATURES COMPLETE] PAPER MODE
                Trading date: %s
                Feature snapshot: %s
                Eligible vectors: %d
                Withheld instruments: %d
                Quality and manifest verification passed.
                Feature storage only; no signal, order, or trading action was created.
                """.formatted(outcome.targetDate(), outcome.featureSnapshotRunId(),
                outcome.eligibleCount(), outcome.withheldCount()).strip();
    }

    static String warningMessage(NotificationOutcome outcome) {
        return """
                [DAILY FEATURES WARNING] PAPER MODE
                Trading date: %s
                Automation status: %s
                Reason: %s
                No feature snapshot is eligible for downstream use.
                No signal, order, or trading action was created; review is required.
                """.formatted(outcome.targetDate(), outcome.status(), outcome.lastErrorCode()).strip();
    }

    record NotificationOutcome(
            LocalDate targetDate,
            UUID dailyRunId,
            UUID featureSnapshotRunId,
            String status,
            String manifestHash,
            Integer eligibleCount,
            Integer withheldCount,
            String lastErrorCode
    ) {
    }

    private record ClaimedWork(long id, LocalDate targetDate, UUID dailyRunId, int attempts) {
    }

    private record AutomationRow(
            String status,
            int attempts,
            UUID dailyRunId,
            UUID featureSnapshotRunId,
            String manifestHash,
            Integer eligibleCount,
            Integer withheldCount,
            String lastErrorCode,
            String notificationStatus
    ) {
    }
}
