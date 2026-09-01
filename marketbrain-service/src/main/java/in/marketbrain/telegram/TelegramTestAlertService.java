package in.marketbrain.telegram;

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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
@ConditionalOnProperty(
        prefix = "marketbrain.telegram",
        name = {"enabled", "test-alerts-enabled"},
        havingValue = "true")
class TelegramTestAlertService {

    enum AlertType {
        NOTE, BUY, SELL_HOLDING
    }

    private static final SecureRandom RANDOM = new SecureRandom();

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final JdbcClient jdbc;

    TelegramTestAlertService(
            TelegramBotClient client,
            TelegramStateStore stateStore,
            JdbcClient jdbc
    ) {
        this.client = client;
        this.stateStore = stateStore;
        this.jdbc = jdbc;
    }

    @Transactional
    String send(AlertType type) {
        TelegramBinding binding = stateStore.activeBinding()
                .orElseThrow(() -> new IllegalStateException("Telegram has not been paired."));
        UUID alertId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plus(10, ChronoUnit.MINUTES);

        jdbc.sql("""
                        INSERT INTO alert_notification
                            (id, alert_type, recipient_identity_hash, expires_at,
                             delivery_status, delivery_channel)
                        VALUES
                            (:id, CAST(:alertType AS alert_notification_type), :recipientHash,
                             :expiresAt, 'SENDING', 'TELEGRAM')
                        """)
                .param("id", alertId)
                .param("alertType", type.name())
                .param("recipientHash", TelegramSecurity.identityHash(binding.userId(), binding.chatId()))
                .param("expiresAt", Timestamp.from(expiresAt))
                .update();

        Map<String, Object> replyMarkup = null;
        if (type != AlertType.NOTE) {
            replyMarkup = actionButtons(alertId, expiresAt);
        }

        String externalMessageId = client.sendMessage(binding.chatId(), messageFor(type), replyMarkup);
        jdbc.sql("""
                        UPDATE alert_notification
                        SET external_message_id = :externalMessageId,
                            sent_at = CURRENT_TIMESTAMP,
                            delivery_status = 'SENT'
                        WHERE id = :id
                        """)
                .param("externalMessageId", externalMessageId)
                .param("id", alertId)
                .update();
        return externalMessageId;
    }

    private Map<String, Object> actionButtons(UUID alertId, Instant expiresAt) {
        List<Map<String, String>> row = new ArrayList<>();
        row.add(button(alertId, "APPROVE", "APPROVE", expiresAt));
        row.add(button(alertId, "REJECT", "REJECT", expiresAt));
        row.add(button(alertId, "DETAILS", "DETAILS", expiresAt));
        return Map.of("inline_keyboard", List.of(row));
    }

    private Map<String, String> button(
            UUID alertId,
            String label,
            String action,
            Instant expiresAt
    ) {
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
                .param("tokenHash", TelegramSecurity.sha256(rawToken))
                .param("expiresAt", Timestamp.from(expiresAt))
                .param("idempotencyKey", "CREATED:" + actionId)
                .update();

        var button = new LinkedHashMap<String, String>();
        button.put("text", label);
        button.put("callback_data", "mb:" + rawToken);
        return button;
    }

    private String randomToken() {
        byte[] bytes = new byte[18];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String messageFor(AlertType type) {
        return switch (type) {
            case NOTE -> """
                    [TEST NOTE] PAPER MODE
                    Preparation notice only. No action is required.
                    This verifies private Telegram delivery; it is not a market recommendation.
                    """.strip();
            case BUY -> """
                    [TEST BUY] PAPER MODE
                    Symbol: TEST-EQ
                    This is not a market recommendation and cannot create a real order.
                    APPROVE is intentionally blocked until fresh-price and risk revalidation are connected.
                    """.strip();
            case SELL_HOLDING -> """
                    [TEST SELL_HOLDING] PAPER MODE
                    Symbol: TEST-EQ
                    This is not a market recommendation and cannot create a real order.
                    APPROVE is intentionally blocked until fresh-price and risk revalidation are connected.
                    """.strip();
        };
    }
}
