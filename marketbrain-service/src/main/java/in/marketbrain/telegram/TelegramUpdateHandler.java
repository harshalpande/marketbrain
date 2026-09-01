package in.marketbrain.telegram;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
class TelegramUpdateHandler {

    private static final String PRIVATE_CHAT = "private";
    private static final String ACTION_PREFIX = "mb:";

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final TelegramActionProcessor actionProcessor;
    private final String pairingCode;

    TelegramUpdateHandler(
            TelegramBotClient client,
            TelegramStateStore stateStore,
            TelegramActionProcessor actionProcessor,
            MarketBrainProperties properties
    ) {
        this.client = client;
        this.stateStore = stateStore;
        this.actionProcessor = actionProcessor;
        this.pairingCode = properties.telegram().pairingCode();
    }

    void handle(TelegramUpdate update) {
        if (update.message() != null) {
            handleMessage(update.message());
        }
        if (update.callback() != null) {
            handleCallback(update.callback());
        }
    }

    private void handleMessage(TelegramMessage message) {
        if (!PRIVATE_CHAT.equals(message.chatType())) {
            return;
        }

        var binding = stateStore.activeBinding();
        if (binding.isPresent() && binding.get().matches(message.userId(), message.chatId())) {
            stateStore.recordInteraction(message.userId(), message.chatId());
            handleAuthorizedCommand(message);
            return;
        }

        if (binding.isPresent()) {
            return;
        }

        String text = normalizedCommand(message.text());
        if (text.startsWith("/pair ")) {
            String suppliedCode = text.substring("/pair ".length()).trim();
            if (TelegramSecurity.constantTimeEquals(pairingCode, suppliedCode)
                    && stateStore.pair(new TelegramBinding(
                    message.userId(), message.chatId(), message.displayName()))) {
                client.sendMessage(message.chatId(),
                        "MarketBrain paired successfully in PAPER MODE. Use /status to verify it.", null);
            } else {
                client.sendMessage(message.chatId(), "Pairing failed.", null);
            }
        } else if (text.startsWith("/start")) {
            client.sendMessage(message.chatId(),
                    "MarketBrain is awaiting secure pairing. Send /pair followed by the code stored locally on the server.",
                    null);
        }
    }

    private void handleAuthorizedCommand(TelegramMessage message) {
        String command = normalizedCommand(message.text());
        switch (command) {
            case "/start", "/status" -> client.sendMessage(message.chatId(),
                    "MarketBrain is connected. Mode: PAPER. Real broker execution: disabled.", null);
            case "/help" -> client.sendMessage(message.chatId(),
                    "Commands: /status and /help. Action buttons appear only on actionable alerts.", null);
            default -> {
                if (command.startsWith("/")) {
                    client.sendMessage(message.chatId(), "Unknown command. Use /help.", null);
                }
            }
        }
    }

    private void handleCallback(TelegramCallback callback) {
        if (!PRIVATE_CHAT.equals(callback.chatType())) {
            return;
        }
        var binding = stateStore.activeBinding();
        if (binding.isEmpty() || !binding.get().matches(callback.userId(), callback.chatId())) {
            client.answerCallback(callback.callbackId(), "Unauthorized action.", true);
            return;
        }
        if (!callback.data().startsWith(ACTION_PREFIX)) {
            client.answerCallback(callback.callbackId(), "Invalid action.", true);
            return;
        }

        stateStore.recordInteraction(callback.userId(), callback.chatId());
        TelegramActionResult result = actionProcessor.process(
                callback, callback.data().substring(ACTION_PREFIX.length()));
        client.answerCallback(callback.callbackId(), result.message(), result.showAlert());
    }

    private String normalizedCommand(String text) {
        if (text == null) {
            return "";
        }
        String normalized = text.trim();
        int botSuffix = normalized.indexOf('@');
        int argument = normalized.indexOf(' ');
        if (botSuffix > 0 && (argument < 0 || botSuffix < argument)) {
            int suffixEnd = argument < 0 ? normalized.length() : argument;
            normalized = normalized.substring(0, botSuffix) + normalized.substring(suffixEnd);
        }
        return normalized;
    }
}
