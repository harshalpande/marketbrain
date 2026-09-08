package in.marketbrain.telegram;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class TelegramPollingBackoffTest {

    @Test
    void backsOffExponentiallyAndCapsAtFiveMinutes() {
        TelegramPollingBackoff backoff = new TelegramPollingBackoff();
        Instant now = Instant.parse("2026-09-08T13:34:30Z");

        assertThat(backoff.registerFailure(now).toSeconds()).isEqualTo(5);
        assertThat(backoff.canAttempt(now.plusSeconds(4))).isFalse();
        assertThat(backoff.canAttempt(now.plusSeconds(5))).isTrue();

        long delay = 0;
        for (int failure = 0; failure < 10; failure++) {
            delay = backoff.registerFailure(now).toSeconds();
        }
        assertThat(delay).isEqualTo(300);
    }

    @Test
    void successfulPollResetsTheFailureWindow() {
        TelegramPollingBackoff backoff = new TelegramPollingBackoff();
        Instant now = Instant.parse("2026-09-08T13:34:30Z");
        backoff.registerFailure(now);
        backoff.registerFailure(now);

        backoff.reset();

        assertThat(backoff.canAttempt(now)).isTrue();
        assertThat(backoff.registerFailure(now).toSeconds()).isEqualTo(5);
    }
}
