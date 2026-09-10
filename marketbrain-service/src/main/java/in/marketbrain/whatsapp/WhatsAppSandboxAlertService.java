package in.marketbrain.whatsapp;

import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

@Service
@ConditionalOnProperty(
        prefix = "marketbrain.whatsapp",
        name = {"enabled", "test-alerts-enabled"},
        havingValue = "true")
class WhatsAppSandboxAlertService {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final List<String> ACTIONS = List.of("APPROVE", "REJECT", "DETAILS");

    private final WhatsAppCloudClient client;
    private final WhatsAppProperties properties;
    private final MarketBrainProperties marketBrainProperties;
    private final JdbcClient jdbc;

    WhatsAppSandboxAlertService(
            WhatsAppCloudClient client,
            WhatsAppProperties properties,
            MarketBrainProperties marketBrainProperties,
            JdbcClient jdbc
    ) {
        this.client = client;
        this.properties = properties;
        this.marketBrainProperties = marketBrainProperties;
        this.jdbc = jdbc;
    }

    @Transactional
    WhatsAppSandboxAlertStatus send() {
        validateSafetyBoundary();
        UUID alertId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plus(10, ChronoUnit.MINUTES);

        jdbc.sql("""
                        INSERT INTO alert_notification
                            (id, alert_type, recipient_identity_hash, expires_at,
                             delivery_status, delivery_channel)
                        VALUES
                            (:id, 'BUY', :recipientHash, :expiresAt,
                             'SENDING', 'WHATSAPP')
                        """)
                .param("id", alertId)
                .param("recipientHash", recipientHash(properties.allowedWaId()))
                .param("expiresAt", Timestamp.from(expiresAt))
                .update();

        List<WhatsAppCloudClient.ReplyButton> buttons = new ArrayList<>();
        for (String action : ACTIONS) {
            String rawToken = randomToken();
            UUID actionId = UUID.randomUUID();
            jdbc.sql("""
                            INSERT INTO alert_action
                                (id, alert_notification_id, action, action_token_hash,
                                 expires_at, idempotency_key)
                            VALUES
                                (:id, :alertId, CAST(:action AS alert_action_type), :tokenHash,
                                 :expiresAt, :idempotencyKey)
                            """)
                    .param("id", actionId)
                    .param("alertId", alertId)
                    .param("action", action)
                    .param("tokenHash", WhatsAppSecurity.sha256(rawToken))
                    .param("expiresAt", Timestamp.from(expiresAt))
                    .param("idempotencyKey", "WHATSAPP:CREATED:" + actionId)
                    .update();
            buttons.add(new WhatsAppCloudClient.ReplyButton("mb:" + rawToken, action));
        }

        String providerMessageId = client.sendInteractiveTestAlert(buttons);
        jdbc.sql("""
                        UPDATE alert_notification
                        SET external_message_id = :externalMessageId,
                            sent_at = CURRENT_TIMESTAMP,
                            delivery_status = 'SENT'
                        WHERE id = :id
                        """)
                .param("externalMessageId", recipientHash(providerMessageId))
                .param("id", alertId)
                .update();
        return status(alertId);
    }

    WhatsAppSandboxAlertStatus status(UUID alertId) {
        AlertHeader header = jdbc.sql("""
                        SELECT alert_type::text AS alert_type,
                               delivery_status,
                               expires_at
                        FROM alert_notification
                        WHERE id = :id
                          AND delivery_channel = 'WHATSAPP'
                        """)
                .param("id", alertId)
                .query((rs, rowNum) -> new AlertHeader(
                        rs.getString("alert_type"),
                        rs.getString("delivery_status"),
                        rs.getTimestamp("expires_at").toInstant()))
                .optional()
                .orElseThrow(() -> new IllegalArgumentException("WhatsApp sandbox alert was not found."));

        List<WhatsAppSandboxAlertStatus.ActionStatus> actions = jdbc.sql("""
                        SELECT action::text AS action, processed, processing_result
                        FROM alert_action
                        WHERE alert_notification_id = :alertId
                        ORDER BY CASE action::text
                            WHEN 'APPROVE' THEN 1
                            WHEN 'REJECT' THEN 2
                            ELSE 3
                        END
                        """)
                .param("alertId", alertId)
                .query((rs, rowNum) -> new WhatsAppSandboxAlertStatus.ActionStatus(
                        rs.getString("action"),
                        rs.getBoolean("processed"),
                        rs.getString("processing_result")))
                .list();

        int processed = (int) actions.stream().filter(
                WhatsAppSandboxAlertStatus.ActionStatus::processed).count();
        return new WhatsAppSandboxAlertStatus(
                header.deliveryStatus(), alertId, header.alertType(), header.expiresAt(),
                processed, actions, false, marketBrainProperties.executionMode());
    }

    private void validateSafetyBoundary() {
        if (!properties.sandboxMode()) {
            throw new IllegalStateException("WhatsApp test alerts require sandbox mode.");
        }
        if (!"PAPER".equals(marketBrainProperties.executionMode())) {
            throw new IllegalStateException("WhatsApp test alerts require PAPER mode.");
        }
        if (!properties.isOutboundConfigured()) {
            throw new IllegalStateException("WhatsApp outbound configuration is incomplete.");
        }
    }

    private String recipientHash(String value) {
        return WhatsAppSecurity.hmacSha256(value, properties.appSecret());
    }

    private String randomToken() {
        byte[] bytes = new byte[18];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private record AlertHeader(String alertType, String deliveryStatus, Instant expiresAt) {
    }
}
