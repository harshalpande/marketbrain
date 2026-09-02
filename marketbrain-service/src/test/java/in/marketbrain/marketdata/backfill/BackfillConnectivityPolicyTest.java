package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

class BackfillConnectivityPolicyTest {

    private final BackfillConnectivityPolicy policy = new BackfillConnectivityPolicy();

    @Test
    void separatesTransientInfrastructureFailuresFromDataAndAuthorizationFailures() {
        assertThat(policy.isTransientInfrastructureFailure("CONNECTION_FAILED")).isTrue();
        assertThat(policy.isTransientInfrastructureFailure("RATE_LIMITED")).isTrue();
        assertThat(policy.isTransientInfrastructureFailure("PROVIDER_UNAVAILABLE")).isTrue();
        assertThat(policy.isTransientInfrastructureFailure("INVALID_PROVIDER_RESPONSE")).isFalse();
        assertThat(policy.isTransientInfrastructureFailure("PROVIDER_ERROR")).isFalse();
    }

    @Test
    void appliesOneFiveAndFifteenMinuteBackoff() {
        assertThat(policy.retryDelay(1)).isEqualTo(Duration.ofMinutes(1));
        assertThat(policy.retryDelay(2)).isEqualTo(Duration.ofMinutes(5));
        assertThat(policy.retryDelay(3)).isEqualTo(Duration.ofMinutes(15));
        assertThat(policy.retryDelay(25)).isEqualTo(Duration.ofMinutes(15));
    }
}
