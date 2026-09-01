package in.marketbrain.telegram;

import com.fasterxml.jackson.databind.JsonNode;
import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Component
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
class TelegramBotClient {

    private final RestClient restClient;
    private final int longPollTimeoutSeconds;

    TelegramBotClient(RestClient.Builder builder, MarketBrainProperties properties) {
        var telegram = properties.telegram();
        if (!telegram.isConfigured()) {
            throw new IllegalStateException(
                    "Telegram is enabled but its bot token or pairing code is missing.");
        }
        this.restClient = builder
                .baseUrl("https://api.telegram.org/bot" + telegram.botToken())
                .build();
        this.longPollTimeoutSeconds = telegram.longPollTimeoutSeconds();
    }

    List<TelegramUpdate> getUpdates(long offset) {
        JsonNode response = post("/getUpdates", Map.of(
                "offset", offset,
                "timeout", longPollTimeoutSeconds,
                "allowed_updates", List.of("message", "callback_query")
        ));

        var updates = new ArrayList<TelegramUpdate>();
        for (JsonNode node : response.path("result")) {
            updates.add(toUpdate(node));
        }
        return updates;
    }

    String sendMessage(long chatId, String text, Map<String, Object> replyMarkup) {
        var body = new java.util.LinkedHashMap<String, Object>();
        body.put("chat_id", chatId);
        body.put("text", text);
        if (replyMarkup != null && !replyMarkup.isEmpty()) {
            body.put("reply_markup", replyMarkup);
        }
        return post("/sendMessage", body).path("result").path("message_id").asText();
    }

    void answerCallback(String callbackId, String text, boolean showAlert) {
        post("/answerCallbackQuery", Map.of(
                "callback_query_id", callbackId,
                "text", text,
                "show_alert", showAlert
        ));
    }

    private JsonNode post(String path, Object body) {
        try {
            JsonNode response = restClient.post()
                    .uri(path)
                    .body(body)
                    .retrieve()
                    .body(JsonNode.class);
            if (response == null || !response.path("ok").asBoolean(false)) {
                throw new TelegramTransportException();
            }
            return response;
        } catch (RestClientException exception) {
            // Do not propagate the provider exception: its message can contain
            // the token-bearing Telegram URL.
            throw new TelegramTransportException();
        }
    }

    private TelegramUpdate toUpdate(JsonNode node) {
        TelegramMessage message = null;
        if (node.has("message")) {
            JsonNode messageNode = node.path("message");
            JsonNode chat = messageNode.path("chat");
            JsonNode from = messageNode.path("from");
            message = new TelegramMessage(
                    chat.path("id").asLong(),
                    chat.path("type").asText(),
                    from.path("id").asLong(),
                    displayName(from),
                    messageNode.path("text").asText("")
            );
        }

        TelegramCallback callback = null;
        if (node.has("callback_query")) {
            JsonNode callbackNode = node.path("callback_query");
            JsonNode from = callbackNode.path("from");
            JsonNode chat = callbackNode.path("message").path("chat");
            callback = new TelegramCallback(
                    callbackNode.path("id").asText(),
                    chat.path("id").asLong(),
                    chat.path("type").asText(),
                    from.path("id").asLong(),
                    callbackNode.path("data").asText("")
            );
        }
        return new TelegramUpdate(node.path("update_id").asLong(), message, callback);
    }

    private String displayName(JsonNode from) {
        String first = from.path("first_name").asText("").trim();
        String last = from.path("last_name").asText("").trim();
        return (first + " " + last).trim();
    }

    static final class TelegramTransportException extends RuntimeException {
        TelegramTransportException() {
            super("Telegram request failed without exposing provider details.");
        }
    }
}
