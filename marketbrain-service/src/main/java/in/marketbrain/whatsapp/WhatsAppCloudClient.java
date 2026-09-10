package in.marketbrain.whatsapp;

import com.fasterxml.jackson.databind.JsonNode;
import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
class WhatsAppCloudClient {

    record ReplyButton(String id, String title) {
    }

    private final RestClient restClient;
    private final WhatsAppProperties properties;

    @Autowired
    WhatsAppCloudClient(RestClient.Builder builder, WhatsAppProperties properties) {
        this(builder.baseUrl("https://graph.facebook.com").build(), properties);
    }

    WhatsAppCloudClient(RestClient restClient, WhatsAppProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    String sendInteractiveTestAlert(List<ReplyButton> buttons) {
        var interactive = new LinkedHashMap<String, Object>();
        interactive.put("type", "button");
        interactive.put("body", Map.of("text", """
                [TEST BUY] MARKETBRAIN PAPER MODE
                Symbol: TEST-EQ
                This is an integration test, not a market recommendation.
                APPROVE cannot create a PAPER fill or real order.
                """.strip()));
        interactive.put("footer", Map.of("text", "Expires in 10 minutes - no trading action"));
        interactive.put("action", Map.of(
                "buttons", buttons.stream()
                        .map(button -> Map.of(
                                "type", "reply",
                                "reply", Map.of("id", button.id(), "title", button.title())))
                        .toList()));

        return send(Map.of(
                "messaging_product", "whatsapp",
                "recipient_type", "individual",
                "to", properties.allowedWaId(),
                "type", "interactive",
                "interactive", interactive), OutboundPurpose.TEST_ACTION);
    }

    void sendActionAcknowledgement(String text) {
        send(Map.of(
                "messaging_product", "whatsapp",
                "recipient_type", "individual",
                "to", properties.allowedWaId(),
                "type", "text",
                "text", Map.of("preview_url", false, "body", text)),
                OutboundPurpose.TEST_ACTION);
    }

    String sendSystemNote(String text) {
        return send(Map.of(
                "messaging_product", "whatsapp",
                "recipient_type", "individual",
                "to", properties.allowedWaId(),
                "type", "text",
                "text", Map.of("preview_url", false, "body", text)),
                OutboundPurpose.SYSTEM_NOTIFICATION);
    }

    private String send(Object body, OutboundPurpose purpose) {
        validateOutboundBoundary(purpose);
        try {
            JsonNode response = restClient.post()
                    .uri("/{version}/{phoneNumberId}/messages",
                            properties.graphVersion(), properties.phoneNumberId())
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + properties.accessToken())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .body(JsonNode.class);
            String messageId = response == null
                    ? ""
                    : response.path("messages").path(0).path("id").asText("");
            if (messageId.isBlank()) {
                throw new WhatsAppTransportException();
            }
            return messageId;
        } catch (RestClientException exception) {
            // Provider exceptions may contain request details. Never propagate them.
            throw new WhatsAppTransportException();
        }
    }

    private void validateOutboundBoundary(OutboundPurpose purpose) {
        if (!properties.enabled() || !properties.sandboxMode()
                || !properties.isOutboundConfigured()) {
            throw new IllegalStateException("WhatsApp outbound sandbox delivery is not configured.");
        }
        if (purpose == OutboundPurpose.TEST_ACTION && !properties.testAlertsEnabled()) {
            throw new IllegalStateException("WhatsApp sandbox test alerts are disabled.");
        }
        if (purpose == OutboundPurpose.SYSTEM_NOTIFICATION
                && !properties.notificationsEnabled()) {
            throw new IllegalStateException("WhatsApp system notifications are disabled.");
        }
        if (!properties.graphVersion().matches("v[0-9]+\\.[0-9]+")) {
            throw new IllegalStateException("WhatsApp Graph version configuration is invalid.");
        }
        if (!properties.phoneNumberId().matches("[0-9]+")) {
            throw new IllegalStateException("WhatsApp phone-number ID configuration is invalid.");
        }
        if (!properties.allowedWaId().matches("[0-9]{8,15}")) {
            throw new IllegalStateException("WhatsApp test recipient configuration is invalid.");
        }
    }

    private enum OutboundPurpose {
        TEST_ACTION,
        SYSTEM_NOTIFICATION
    }

    static final class WhatsAppTransportException extends RuntimeException {
        WhatsAppTransportException() {
            super("WhatsApp request failed without exposing provider details.");
        }
    }
}
