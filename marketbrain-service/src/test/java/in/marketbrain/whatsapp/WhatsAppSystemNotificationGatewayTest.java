package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import in.marketbrain.notification.SystemNotificationDeliveryLedger;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WhatsAppSystemNotificationGatewayTest {

    @Test
    void deliversAndAuditsOneSystemNote() {
        WhatsAppCloudClient client = mock(WhatsAppCloudClient.class);
        SystemNotificationDeliveryLedger ledger = mock(SystemNotificationDeliveryLedger.class);
        UUID notificationId = UUID.randomUUID();
        when(ledger.claim(anyString(), anyString(), anyString()))
                .thenReturn(new SystemNotificationDeliveryLedger.DeliveryClaim(notificationId, true));
        when(client.sendSystemNote("same-message")).thenReturn("wamid.system");
        WhatsAppSystemNotificationGateway gateway =
                new WhatsAppSystemNotificationGateway(client, properties(), ledger);

        gateway.sendNote("dedup-key", "same-message");

        verify(client).sendSystemNote("same-message");
        verify(ledger).markSent(org.mockito.ArgumentMatchers.eq(notificationId), anyString());
    }

    @Test
    void alreadySentDeliveryIsNotSentToMetaAgain() {
        WhatsAppCloudClient client = mock(WhatsAppCloudClient.class);
        SystemNotificationDeliveryLedger ledger = mock(SystemNotificationDeliveryLedger.class);
        when(ledger.claim(anyString(), anyString(), anyString()))
                .thenReturn(new SystemNotificationDeliveryLedger.DeliveryClaim(
                        UUID.randomUUID(), false));
        WhatsAppSystemNotificationGateway gateway =
                new WhatsAppSystemNotificationGateway(client, properties(), ledger);

        gateway.sendNote("dedup-key", "same-message");

        verify(client, never()).sendSystemNote(anyString());
    }

    private WhatsAppProperties properties() {
        return new WhatsAppProperties(
                true, true, false, true, "v26.0", "123456789", "987654321",
                "local-test-token", "local-test-app-secret",
                "0123456789abcdef0123456789abcdef", "919999999999");
    }
}
