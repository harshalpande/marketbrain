package in.marketbrain.whatsapp;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

@Service
class WhatsAppWebhookService {

    private final ObjectMapper objectMapper;
    private final WhatsAppProperties properties;
    private final WhatsAppWebhookEventStore store;

    WhatsAppWebhookService(
            ObjectMapper objectMapper,
            WhatsAppProperties properties,
            WhatsAppWebhookEventStore store
    ) {
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.store = store;
    }

    WhatsAppWebhookResult receive(byte[] payload) throws IOException {
        JsonNode root = objectMapper.readTree(payload);
        String payloadHash = WhatsAppSecurity.sha256(payload);
        List<WhatsAppWebhookEvent> events = parse(root, payloadHash);

        int accepted = 0;
        int ignored = 0;
        int duplicates = 0;
        for (WhatsAppWebhookEvent event : events) {
            if (!store.save(event)) {
                duplicates++;
            } else if ("ACCEPTED".equals(event.disposition())) {
                accepted++;
            } else {
                ignored++;
            }
        }
        return new WhatsAppWebhookResult(accepted, ignored, duplicates);
    }

    private List<WhatsAppWebhookEvent> parse(JsonNode root, String payloadHash) {
        List<WhatsAppWebhookEvent> events = new ArrayList<>();
        if (!"whatsapp_business_account".equals(root.path("object").asText())) {
            return events;
        }

        for (JsonNode entry : root.path("entry")) {
            String wabaId = entry.path("id").asText("");
            for (JsonNode change : entry.path("changes")) {
                JsonNode value = change.path("value");
                String phoneNumberId = value.path("metadata").path("phone_number_id").asText("");
                boolean trustedAccount = properties.wabaId().equals(wabaId)
                        && properties.phoneNumberId().equals(phoneNumberId);

                for (JsonNode message : value.path("messages")) {
                    events.add(messageEvent(
                            message, wabaId, phoneNumberId, trustedAccount, payloadHash));
                }
                for (JsonNode status : value.path("statuses")) {
                    events.add(statusEvent(
                            status, wabaId, phoneNumberId, trustedAccount, payloadHash));
                }
            }
        }
        return events;
    }

    private WhatsAppWebhookEvent messageEvent(
            JsonNode message,
            String wabaId,
            String phoneNumberId,
            boolean trustedAccount,
            String payloadHash
    ) {
        String messageId = message.path("id").asText("");
        String participantWaId = message.path("from").asText("");
        String actionPayload = actionPayload(message);
        String kind = actionPayload.isBlank() ? "MESSAGE" : "BUTTON_REPLY";
        boolean allowedParticipant = properties.allowedWaId().equals(participantWaId);
        String eventKey = messageId.isBlank()
                ? "message:" + payloadHash
                : "message:" + messageId;
        return event(
                eventKey,
                kind,
                trustedAccount && allowedParticipant ? "ACCEPTED" : "IGNORED",
                wabaId,
                phoneNumberId,
                participantWaId,
                messageId,
                actionPayload,
                payloadHash);
    }

    private WhatsAppWebhookEvent statusEvent(
            JsonNode status,
            String wabaId,
            String phoneNumberId,
            boolean trustedAccount,
            String payloadHash
    ) {
        String messageId = status.path("id").asText("");
        String participantWaId = status.path("recipient_id").asText("");
        String state = status.path("status").asText("unknown");
        String timestamp = status.path("timestamp").asText("");
        boolean allowedParticipant = properties.allowedWaId().equals(participantWaId);
        String eventKey = "status:" + messageId + ':' + state + ':' + timestamp;
        return event(
                eventKey,
                "MESSAGE_STATUS",
                trustedAccount && allowedParticipant ? "ACCEPTED" : "IGNORED",
                wabaId,
                phoneNumberId,
                participantWaId,
                messageId,
                "",
                payloadHash);
    }

    private WhatsAppWebhookEvent event(
            String eventKey,
            String kind,
            String disposition,
            String wabaId,
            String phoneNumberId,
            String participantWaId,
            String messageId,
            String actionPayload,
            String payloadHash
    ) {
        return new WhatsAppWebhookEvent(
                keyedHash(eventKey),
                kind,
                disposition,
                keyedHash(wabaId),
                nullableKeyedHash(phoneNumberId),
                nullableKeyedHash(participantWaId),
                nullableKeyedHash(messageId),
                nullableKeyedHash(actionPayload),
                payloadHash);
    }

    private String actionPayload(JsonNode message) {
        if ("interactive".equals(message.path("type").asText())
                && "button_reply".equals(message.path("interactive").path("type").asText())) {
            return message.path("interactive").path("button_reply").path("id").asText("");
        }
        if ("button".equals(message.path("type").asText())) {
            return message.path("button").path("payload").asText("");
        }
        return "";
    }

    private String keyedHash(String value) {
        return WhatsAppSecurity.hmacSha256(value, properties.appSecret());
    }

    private String nullableKeyedHash(String value) {
        return value == null || value.isBlank() ? null : keyedHash(value);
    }
}
