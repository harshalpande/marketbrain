package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import in.marketbrain.notification.SystemNotificationDeliveryLedger;
import in.marketbrain.notification.SystemNotificationGateway;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(
        prefix = "marketbrain.whatsapp",
        name = {"enabled", "notifications-enabled"},
        havingValue = "true")
public class WhatsAppSystemNotificationGateway implements SystemNotificationGateway {

    private final WhatsAppCloudClient client;
    private final WhatsAppProperties properties;
    private final SystemNotificationDeliveryLedger deliveryLedger;

    WhatsAppSystemNotificationGateway(
            WhatsAppCloudClient client,
            WhatsAppProperties properties,
            SystemNotificationDeliveryLedger deliveryLedger
    ) {
        this.client = client;
        this.properties = properties;
        this.deliveryLedger = deliveryLedger;
    }

    @Override
    public String channel() {
        return "WHATSAPP";
    }

    @Override
    public void sendNote(String deduplicationKey, String message) {
        var claim = deliveryLedger.claim(
                channel(), deduplicationKey, recipientHash(properties.allowedWaId()));
        if (!claim.deliveryRequired()) {
            return;
        }
        try {
            String externalMessageId = client.sendSystemNote(message);
            deliveryLedger.markSent(
                    claim.notificationId(), recipientHash(externalMessageId));
        } catch (RuntimeException exception) {
            deliveryLedger.markFailed(claim.notificationId());
            throw exception;
        }
    }

    private String recipientHash(String value) {
        return WhatsAppSecurity.hmacSha256(value, properties.appSecret());
    }
}
