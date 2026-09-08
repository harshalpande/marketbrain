package in.marketbrain.marketdata.daily;

import in.marketbrain.notification.SystemNotificationGateway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
public class DailyEnrichmentNotificationService {

    private static final Logger LOGGER = LoggerFactory.getLogger(DailyEnrichmentNotificationService.class);

    private final JdbcTemplate jdbcTemplate;
    private final List<SystemNotificationGateway> notificationGateways;

    public DailyEnrichmentNotificationService(
            JdbcTemplate jdbcTemplate,
            List<SystemNotificationGateway> notificationGateways
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.notificationGateways = notificationGateways;
    }

    public boolean sendCompletion(LocalDate targetDate, UUID runId, String message) {
        return sendOnce(targetDate, runId, "COMPLETION", message);
    }

    public boolean sendWarning(LocalDate targetDate, UUID runId, String message) {
        return sendOnce(targetDate, runId, "WARNING", message);
    }

    public boolean sendFeatureCompletion(LocalDate targetDate, UUID runId, String message) {
        return sendOnce(targetDate, runId, "FEATURE_COMPLETION", message);
    }

    public boolean sendFeatureWarning(LocalDate targetDate, UUID runId, String message) {
        return sendOnce(targetDate, runId, "FEATURE_WARNING", message);
    }

    private boolean sendOnce(LocalDate targetDate, UUID runId, String kind, String message) {
        jdbcTemplate.update("""
                INSERT INTO daily_enrichment_notification
                    (target_date, run_id, notice_kind, delivery_status)
                VALUES (?, ?, ?, 'PENDING')
                ON CONFLICT (target_date, notice_kind) DO NOTHING
                """, targetDate, runId, kind);
        List<Long> claims = jdbcTemplate.query("""
                UPDATE daily_enrichment_notification
                SET delivery_status = 'SENDING', attempts = attempts + 1,
                    last_error_code = NULL, updated_at = CURRENT_TIMESTAMP
                WHERE target_date = ? AND notice_kind = ?
                  AND (
                      delivery_status = 'PENDING'
                      OR (delivery_status = 'FAILED'
                          AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '5 minutes')
                      OR (delivery_status = 'SENDING'
                          AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '10 minutes')
                  )
                RETURNING id
                """, (rs, row) -> rs.getLong(1), targetDate, kind);
        if (claims.isEmpty()) {
            return false;
        }
        long noticeId = claims.getFirst();
        if (notificationGateways.isEmpty()) {
            fail(noticeId, "TELEGRAM_NOT_CONFIGURED");
            LOGGER.warn("Daily enrichment {} notice is pending because Telegram is not configured.", kind);
            return false;
        }
        try {
            notificationGateways.getFirst().sendNote(message);
            jdbcTemplate.update("""
                    UPDATE daily_enrichment_notification
                    SET delivery_status = 'SENT', sent_at = CURRENT_TIMESTAMP,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """, noticeId);
            return true;
        } catch (RuntimeException exception) {
            fail(noticeId, "TELEGRAM_DELIVERY_FAILED");
            LOGGER.warn("Daily enrichment {} notice delivery failed safely.", kind);
            return false;
        }
    }

    private void fail(long noticeId, String errorCode) {
        jdbcTemplate.update("""
                UPDATE daily_enrichment_notification
                SET delivery_status = 'FAILED', last_error_code = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """, errorCode, noticeId);
    }
}
