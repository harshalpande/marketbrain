package in.marketbrain.telegram;

import java.time.Duration;
import java.time.Instant;

final class TelegramPollingBackoff {

    private static final long INITIAL_DELAY_SECONDS = 5;
    private static final long MAXIMUM_DELAY_SECONDS = 300;

    private int consecutiveFailures;
    private Instant retryAt = Instant.MIN;

    boolean canAttempt(Instant now) {
        return !now.isBefore(retryAt);
    }

    Duration registerFailure(Instant now) {
        consecutiveFailures++;
        int exponent = Math.min(consecutiveFailures - 1, 6);
        long delaySeconds = Math.min(MAXIMUM_DELAY_SECONDS, INITIAL_DELAY_SECONDS << exponent);
        retryAt = now.plusSeconds(delaySeconds);
        return Duration.ofSeconds(delaySeconds);
    }

    void reset() {
        consecutiveFailures = 0;
        retryAt = Instant.MIN;
    }
}
