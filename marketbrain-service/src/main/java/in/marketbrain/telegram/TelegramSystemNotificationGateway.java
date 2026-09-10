package in.marketbrain.telegram;

import in.marketbrain.notification.SystemNotificationGateway;
import in.marketbrain.notification.SystemNotificationDeliveryLedger;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
public class TelegramSystemNotificationGateway implements SystemNotificationGateway {

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final SystemNotificationDeliveryLedger deliveryLedger;

    TelegramSystemNotificationGateway(
            TelegramBotClient client,
            TelegramStateStore stateStore,
            SystemNotificationDeliveryLedger deliveryLedger
    ) {
        this.client = client;
        this.stateStore = stateStore;
        this.deliveryLedger = deliveryLedger;
    }

    @Override
    public String channel() {
        return "TELEGRAM";
    }

    @Override
    public void sendNote(String deduplicationKey, String message) {
        TelegramBinding binding = stateStore.activeBinding()
                .orElseThrow(() -> new IllegalStateException("Telegram has not been paired."));
        var claim = deliveryLedger.claim(
                channel(), deduplicationKey,
                TelegramSecurity.identityHash(binding.userId(), binding.chatId()));
        if (!claim.deliveryRequired()) {
            return;
        }
        try {
            String externalMessageId = client.sendMessage(binding.chatId(), message, Map.of());
            deliveryLedger.markSent(claim.notificationId(), externalMessageId);
        } catch (RuntimeException exception) {
            deliveryLedger.markFailed(claim.notificationId());
            throw exception;
        }
    }
}
