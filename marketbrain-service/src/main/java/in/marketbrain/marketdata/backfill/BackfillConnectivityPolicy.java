package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Set;

@Component
public class BackfillConnectivityPolicy {

    private static final Set<String> TRANSIENT_FAILURES = Set.of(
            "CONNECTION_FAILED",
            "RATE_LIMITED",
            "PROVIDER_UNAVAILABLE"
    );

    public boolean isTransientInfrastructureFailure(String status) {
        return TRANSIENT_FAILURES.contains(status);
    }

    public Duration retryDelay(int consecutiveFailureCount) {
        if (consecutiveFailureCount <= 1) {
            return Duration.ofMinutes(1);
        }
        if (consecutiveFailureCount == 2) {
            return Duration.ofMinutes(5);
        }
        return Duration.ofMinutes(15);
    }
}
