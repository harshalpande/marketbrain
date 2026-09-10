package in.marketbrain.whatsapp;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.WhatsAppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

@Service
class WhatsAppWebhookService {

    private static final Logger LOGGER = LoggerFactory.getLogger(WhatsAppWebhookService.class);
    private static final String ACTION_PREFIX = "mb:";

    private final ObjectMapper objectMapper;
    private final WhatsAppProperties properties;
    private final WhatsAppWebhookEventStore store;
    private final WhatsAppActionProcessor actionProcessor;
    private final WhatsAppCloudClient client;

    WhatsAppWebhookService(
            ObjectMapper objectMapper,
            WhatsAppProperties properties,
            WhatsAppWebhookEventStore store,
            WhatsAppActionProcessor actionProcessor,
            WhatsAppCloudClient client
    ) {
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.store = store;
        this.actionProcessor = actionProcessor;
        this.client = client;
    }

    @Transactional
    WhatsAppWebhookResult receive(byte[] payload) throws IOException {
        JsonNode root = objectMapper.readTree(payload);
        String payloadHash = WhatsAppSecurity.sha256(payload);
        List<ParsedEvent> events = parse(root, payloadHash);

        int accepted = 0;
        int ignored = 0;
        int duplicates = 0;
        for (ParsedEvent parsed : events) {
            WhatsAppWebhookEvent event = parsed.event();
            if (!store.save(event)) {
                duplicates++;
            } else if ("ACCEPTED".equals(event.disposition())) {
                accepted++;
                handleAction(parsed);
            } else {
                ignored++;
            }
        }
        return new WhatsAppWebhookResult(accepted, ignored, duplicates);
    }

    private List<ParsedEvent> parse(JsonNode root, String payloadHash) {
        List<ParsedEvent> events = new ArrayList<>();
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
                    events.add(new ParsedEvent(
                            statusEvent(status, wabaId, phoneNumberId, trustedAccount, payloadHash),
                            "", "", ""));
                }
            }
        }
        return events;
    }

    private ParsedEvent messageEvent(
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
        WhatsAppWebhookEvent event = event(
                eventKey,
                kind,
                trustedAccount && allowedParticipant ? "ACCEPTED" : "IGNORED",
                wabaId,
                phoneNumberId,
                participantWaId,
                messageId,
                actionPayload,
                payloadHash);
        return new ParsedEvent(event, actionPayload, participantWaId, messageId);
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

    private void handleAction(ParsedEvent parsed) {
        if (!"BUTTON_REPLY".equals(parsed.event().eventKind())
                || !parsed.actionPayload().startsWith(ACTION_PREFIX)) {
            return;
        }

        WhatsAppActionResult result = actionProcessor.process(
                parsed.participantWaId(),
                parsed.providerMessageId(),
                parsed.actionPayload().substring(ACTION_PREFIX.length()));
        LOGGER.info(
                "WhatsApp sandbox button handled: action={}, result={}, actionExecutionEnabled=false",
                result.action(), result.result());
        if (result.notifyRecipient()) {
            try {
                client.sendActionAcknowledgement(result.acknowledgement());
            } catch (WhatsAppCloudClient.WhatsAppTransportException exception) {
                LOGGER.warn("WhatsApp action acknowledgement failed; the audited decision remains recorded.");
            }
        }
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

    private record ParsedEvent(
            WhatsAppWebhookEvent event,
            String actionPayload,
            String participantWaId,
            String providerMessageId
    ) {
    }
}
