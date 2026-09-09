package in.marketbrain.whatsapp;

import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.WhatsAppProperties;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WhatsAppWebhookServiceTest {

    @Test
    void storesOnlyHashedMetadataForAnAllowedButtonReply() throws Exception {
        WhatsAppWebhookEventStore store = mock(WhatsAppWebhookEventStore.class);
        when(store.save(org.mockito.ArgumentMatchers.any())).thenReturn(true);
        WhatsAppWebhookService service = new WhatsAppWebhookService(
                new ObjectMapper(), properties(), store);
        byte[] payload = payload("waba-id", "phone-number-id", "919999999999")
                .getBytes(StandardCharsets.UTF_8);

        WhatsAppWebhookResult result = service.receive(payload);

        ArgumentCaptor<WhatsAppWebhookEvent> captor =
                ArgumentCaptor.forClass(WhatsAppWebhookEvent.class);
        verify(store).save(captor.capture());
        WhatsAppWebhookEvent event = captor.getValue();
        assertThat(result).isEqualTo(new WhatsAppWebhookResult(1, 0, 0));
        assertThat(event.eventKind()).isEqualTo("BUTTON_REPLY");
        assertThat(event.disposition()).isEqualTo("ACCEPTED");
        assertThat(event.wabaIdHash()).hasSize(64).doesNotContain("waba-id");
        assertThat(event.participantWaIdHash()).hasSize(64).doesNotContain("919999999999");
        assertThat(event.actionPayloadHash()).hasSize(64).doesNotContain("opaque-action-token");
    }

    @Test
    void recordsButIgnoresAnUnexpectedParticipant() throws Exception {
        WhatsAppWebhookEventStore store = mock(WhatsAppWebhookEventStore.class);
        when(store.save(org.mockito.ArgumentMatchers.any())).thenReturn(true);
        WhatsAppWebhookService service = new WhatsAppWebhookService(
                new ObjectMapper(), properties(), store);

        WhatsAppWebhookResult result = service.receive(
                payload("waba-id", "phone-number-id", "918888888888")
                        .getBytes(StandardCharsets.UTF_8));

        ArgumentCaptor<WhatsAppWebhookEvent> captor =
                ArgumentCaptor.forClass(WhatsAppWebhookEvent.class);
        verify(store).save(captor.capture());
        assertThat(result).isEqualTo(new WhatsAppWebhookResult(0, 1, 0));
        assertThat(captor.getValue().disposition()).isEqualTo("IGNORED");
    }

    private WhatsAppProperties properties() {
        return new WhatsAppProperties(
                true,
                true,
                "v25.0",
                "phone-number-id",
                "waba-id",
                "temporary-test-token",
                "local-test-app-secret",
                "0123456789abcdef0123456789abcdef",
                "919999999999");
    }

    private String payload(String wabaId, String phoneNumberId, String from) {
        return """
                {
                  "object": "whatsapp_business_account",
                  "entry": [{
                    "id": "%s",
                    "changes": [{
                      "field": "messages",
                      "value": {
                        "messaging_product": "whatsapp",
                        "metadata": {"phone_number_id": "%s"},
                        "messages": [{
                          "from": "%s",
                          "id": "wamid.test-message",
                          "timestamp": "1788950000",
                          "type": "interactive",
                          "interactive": {
                            "type": "button_reply",
                            "button_reply": {
                              "id": "opaque-action-token",
                              "title": "DETAILS"
                            }
                          }
                        }]
                      }
                    }]
                  }]
                }
                """.formatted(wabaId, phoneNumberId, from);
    }
}
