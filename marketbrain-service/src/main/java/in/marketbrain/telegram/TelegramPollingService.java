package in.marketbrain.telegram;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

@Component
@ConditionalOnProperty(prefix = "marketbrain.telegram", name = "enabled", havingValue = "true")
class TelegramPollingService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TelegramPollingService.class);

    private final TelegramBotClient client;
    private final TelegramStateStore stateStore;
    private final TelegramUpdateHandler handler;
    private final TelegramPollingBackoff backoff = new TelegramPollingBackoff();

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
        Instant now = Instant.now();
        if (!backoff.canAttempt(now)) {
            return;
        }
        try {
            long offset = stateStore.nextUpdateOffset();
            for (TelegramUpdate update : client.getUpdates(offset)) {
                handler.handle(update);
                stateStore.saveNextUpdateOffset(update.updateId() + 1);
            }
            backoff.reset();
        } catch (RuntimeException exception) {
            // Exception messages are intentionally omitted because provider
            // errors can contain token-bearing URLs.
            Duration retryDelay = backoff.registerFailure(Instant.now());
            LOGGER.warn("Telegram poll failed; retrying safely in {} seconds ({})",
                    retryDelay.toSeconds(), exception.getClass().getSimpleName());
        }
    }
}
