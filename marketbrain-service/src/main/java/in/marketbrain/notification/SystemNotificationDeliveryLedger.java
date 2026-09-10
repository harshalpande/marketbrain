package in.marketbrain.notification;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.UUID;

@Service
public class SystemNotificationDeliveryLedger {

    private final JdbcClient jdbc;

    public SystemNotificationDeliveryLedger(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public DeliveryClaim claim(
            String channel,
            String deduplicationKey,
            String recipientIdentityHash
    ) {
        validate(channel, deduplicationKey, recipientIdentityHash);
        jdbc.sql("""
                        INSERT INTO alert_notification
                            (id, alert_type, recipient_identity_hash, delivery_status,
                             delivery_channel, delivery_deduplication_key)
                        VALUES
                            (:id, 'NOTE', :recipientHash, 'PENDING', :channel, :deduplicationKey)
                        ON CONFLICT (delivery_channel, delivery_deduplication_key) DO NOTHING
                        """)
                .param("id", UUID.randomUUID())
                .param("recipientHash", recipientIdentityHash)
                .param("channel", channel)
                .param("deduplicationKey", deduplicationKey)
                .update();

        List<UUID> claims = jdbc.sql("""
                        UPDATE alert_notification
                        SET delivery_status = 'SENDING', updated_at = CURRENT_TIMESTAMP
                        WHERE delivery_channel = :channel
                          AND delivery_deduplication_key = :deduplicationKey
                          AND (
                              delivery_status IN ('PENDING', 'FAILED')
                              OR (delivery_status = 'SENDING'
                                  AND updated_at <= CURRENT_TIMESTAMP - INTERVAL '10 minutes')
                          )
                        RETURNING id
                        """)
                .param("channel", channel)
                .param("deduplicationKey", deduplicationKey)
                .query(UUID.class)
                .list();
        if (!claims.isEmpty()) {
            return new DeliveryClaim(claims.getFirst(), true);
        }

        DeliveryClaim existing = jdbc.sql("""
                        SELECT id, delivery_status = 'SENT' AS already_sent
                        FROM alert_notification
                        WHERE delivery_channel = :channel
                          AND delivery_deduplication_key = :deduplicationKey
                        """)
                .param("channel", channel)
                .param("deduplicationKey", deduplicationKey)
                .query((resultSet, row) -> new DeliveryClaim(
                        resultSet.getObject("id", UUID.class),
                        !resultSet.getBoolean("already_sent")))
                .single();
        if (existing.deliveryRequired()) {
            throw new IllegalStateException("Notification delivery is already in progress.");
        }
        return existing;
    }

    public void markSent(UUID notificationId, String externalMessageId) {
        int updated = jdbc.sql("""
                        UPDATE alert_notification
                        SET external_message_id = :externalMessageId,
                            sent_at = CURRENT_TIMESTAMP,
                            delivery_status = 'SENT',
                            updated_at = CURRENT_TIMESTAMP
                        WHERE id = :id AND delivery_status = 'SENDING'
                        """)
                .param("externalMessageId", externalMessageId)
                .param("id", notificationId)
                .update();
        if (updated != 1) {
            throw new IllegalStateException("Notification delivery claim changed before completion.");
        }
    }

    public void markFailed(UUID notificationId) {
        jdbc.sql("""
                        UPDATE alert_notification
                        SET delivery_status = 'FAILED', updated_at = CURRENT_TIMESTAMP
                        WHERE id = :id AND delivery_status = 'SENDING'
                        """)
                .param("id", notificationId)
                .update();
    }

    private void validate(String channel, String deduplicationKey, String recipientIdentityHash) {
        if (!("TELEGRAM".equals(channel) || "WHATSAPP".equals(channel))) {
            throw new IllegalArgumentException("Unsupported notification channel.");
        }
        if (deduplicationKey == null || deduplicationKey.isBlank()
                || deduplicationKey.length() > 160) {
            throw new IllegalArgumentException("A bounded notification deduplication key is required.");
        }
        if (recipientIdentityHash == null || recipientIdentityHash.isBlank()) {
            throw new IllegalArgumentException("A recipient identity hash is required.");
        }
    }

    public record DeliveryClaim(UUID notificationId, boolean deliveryRequired) {
    }
}
