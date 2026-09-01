package in.marketbrain.telegram;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
class TelegramPollingService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TelegramPollingService.class);

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final TelegramUpdateHandler handler;

    TelegramPollingService(
            TelegramBotClient client,
            TelegramStateStore stateStore,
            TelegramUpdateHandler handler
    ) {
        this.client = client;
        this.stateStore = stateStore;
        this.handler = handler;
    }

    @Scheduled(fixedDelayString = "${marketbrain.telegram.poll-delay-millis:1000}")
    void poll() {
        try {
            long offset = stateStore.nextUpdateOffset();
            for (TelegramUpdate update : client.getUpdates(offset)) {
                handler.handle(update);
                stateStore.saveNextUpdateOffset(update.updateId() + 1);
            }
        } catch (RuntimeException exception) {
            // Exception messages are intentionally omitted because provider
            // errors can contain token-bearing URLs.
            LOGGER.warn("Telegram poll failed; retrying safely ({})",
                    exception.getClass().getSimpleName());
        }
    }
}
