package in.marketbrain.telegram;

import in.marketbrain.notification.SystemNotificationGateway;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.UUID;

@Service
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
public class TelegramSystemNotificationGateway implements SystemNotificationGateway {

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final JdbcClient jdbc;

    TelegramSystemNotificationGateway(
            TelegramBotClient client,
            TelegramStateStore stateStore,
            JdbcClient jdbc
    ) {
        this.client = client;
        this.stateStore = stateStore;
        this.jdbc = jdbc;
    }

    @Override
    public void sendNote(String message) {
        TelegramBinding binding = stateStore.activeBinding()
                .orElseThrow(() -> new IllegalStateException("Telegram has not been paired."));
        UUID notificationId = UUID.randomUUID();
        jdbc.sql("""
                        INSERT INTO alert_notification
                            (id, alert_type, recipient_identity_hash, delivery_status, delivery_channel)
                        VALUES
                            (:id, 'NOTE', :recipientHash, 'SENDING', 'TELEGRAM')
                        """)
                .param("id", notificationId)
                .param("recipientHash", TelegramSecurity.identityHash(binding.userId(), binding.chatId()))
                .update();
        try {
            String externalMessageId = client.sendMessage(binding.chatId(), message, Map.of());
            jdbc.sql("""
                            UPDATE alert_notification
                            SET external_message_id = :externalMessageId,
                                sent_at = CURRENT_TIMESTAMP,
                                delivery_status = 'SENT'
                            WHERE id = :id
                            """)
                    .param("externalMessageId", externalMessageId)
                    .param("id", notificationId)
                    .update();
        } catch (RuntimeException exception) {
            jdbc.sql("""
                            UPDATE alert_notification
                            SET delivery_status = 'FAILED'
                            WHERE id = :id
                            """)
                    .param("id", notificationId)
                    .update();
            throw exception;
        }
    }
}
