package in.marketbrain.marketdata.paytm;

import in.marketbrain.configuration.MarketBrainProperties;
import java.time.Duration;
import java.util.UUID;
import java.util.function.LongSupplier;
import java.util.function.Supplier;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/** Main-process diagnostic only. No broker authentication, history, quotes or order permission. */
@Component
public final class PaytmApplicationRoute {
    private final String bootId = UUID.randomUUID().toString();
    private final boolean permitted;
    private final LongSupplier nanoTime;
    private final Supplier<PaytmGatewayTransport.Observation> request;
    private long deadline;
    private int remaining;

    @Autowired
    public PaytmApplicationRoute(MarketBrainProperties properties) {
        this("PAPER".equals(properties.executionMode()) && properties.paytmMoney() != null
                && !properties.paytmMoney().enabled()
                && (properties.paytmMoney().accessToken() == null || properties.paytmMoney().accessToken().isBlank()),
                System::nanoTime, () -> {
                    try (var transport = new PaytmGatewayTransport("host.docker.internal", 18889)) {
                        return transport.head();
                    }
                });
    }

    PaytmApplicationRoute(boolean permitted, LongSupplier nanoTime,
                          Supplier<PaytmGatewayTransport.Observation> request) {
        this.permitted = permitted; this.nanoTime = nanoTime; this.request = request;
    }

    public record Receipt(String version, String bootId, String state, String status,
                          int remainingRequests, int httpStatus, boolean tlsVerified, String failureType,
                          boolean applicationProcessVerified, boolean credentialsUsed, boolean ordersEnabled) {}

    private boolean active() { return permitted && remaining > 0 && nanoTime.getAsLong() - deadline < 0; }
    private Receipt receipt(String status, int code, boolean tls, String failure) {
        if (!active()) remaining = 0;
        return new Receipt("PAYTM_APPLICATION_ROUTE_V1", bootId, active() ? "ARMED" : "LOCKED", status,
                remaining, code, tls, failure, true, false, false);
    }
    public synchronized Receipt status() { return receipt("STATUS", 0, false, "NONE"); }
    public synchronized Receipt lock() { remaining = 0; return receipt("LOCKED", 0, false, "NONE"); }
    public synchronized Receipt arm() {
        if (!permitted) return receipt("CONFIGURATION_BLOCKED", 0, false, "NONE");
        // Fixed bounded lease; never restored from disk and never grants broker access.
        deadline = nanoTime.getAsLong() + Duration.ofMinutes(20).toNanos(); remaining = 4;
        return receipt("ARMED", 0, false, "NONE");
    }
    public synchronized Receipt head() {
        if (!active()) return receipt("LOCKED", 0, false, "NONE");
        remaining--;
        try {
            var value = request.get();
            if (!value.tlsVerified()) remaining = 0;
            return receipt(value.status(), value.httpStatus(), value.tlsVerified(), value.failureType());
        } catch (RuntimeException failure) {
            remaining = 0;
            return receipt("TRANSPORT_FAILED", 0, false, "INTERNAL_FAILURE");
        }
    }
}
