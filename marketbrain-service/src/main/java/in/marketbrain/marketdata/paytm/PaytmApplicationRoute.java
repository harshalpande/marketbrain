package in.marketbrain.marketdata.paytm;

import in.marketbrain.configuration.MarketBrainProperties;
import java.util.function.LongSupplier;
import java.util.function.Supplier;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/** Main-process diagnostic only. No broker authentication, history, quotes or order permission. */
@Component
public final class PaytmApplicationRoute {
    private final boolean permitted;
    private final PaytmDiagnosticTimingGuard timing;
    private final Supplier<PaytmGatewayTransport.Observation> request;

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
        this(permitted, nanoTime, System::currentTimeMillis, request);
    }

    PaytmApplicationRoute(boolean permitted, LongSupplier nanoTime, LongSupplier wallMillis,
                          Supplier<PaytmGatewayTransport.Observation> request) {
        this.permitted = permitted; this.timing = new PaytmDiagnosticTimingGuard(nanoTime, wallMillis);
        this.request = request;
    }
    // Authenticated bridge can publish evidence; trusted runtime collector remains pending.
    boolean observeHealth(PaytmDiagnosticTimingGuard.Health evidence) { return timing.observe(evidence); }

    public record Receipt(String version, String bootId, String state, String status,
                          int remainingRequests, int httpStatus, boolean tlsVerified, String failureType,
                          boolean applicationProcessVerified, boolean credentialsUsed, boolean ordersEnabled) {}

    private Receipt receipt(String status, int code, boolean tls, String failure) {
        var decision = timing.status();
        return new Receipt("PAYTM_APPLICATION_ROUTE_V1", timing.bootId(),
                permitted && decision.diagnosticAllowed() ? "ARMED" : "LOCKED", status,
                decision.remainingRequests(), code, tls, failure, true, false, false);
    }
    public synchronized Receipt status() { return receipt("STATUS", 0, false, timing.status().reason()); }
    public synchronized Receipt lock() { timing.lock(); return receipt("LOCKED", 0, false, "NONE"); }
    public synchronized Receipt arm() {
        if (!permitted) return receipt("CONFIGURATION_BLOCKED", 0, false, "NONE");
        var decision = timing.arm();
        return receipt(decision.diagnosticAllowed() ? "ARMED" : "TIMING_BLOCKED", 0, false, decision.reason());
    }
    public synchronized Receipt head() {
        if (!permitted) return receipt("LOCKED", 0, false, "CONFIGURATION_BLOCKED");
        var permission = timing.checkAndConsume();
        if (!permission.diagnosticAllowed()) return receipt("LOCKED", 0, false, permission.reason());
        try {
            var value = request.get();
            var completion = timing.validateCompletion();
            if (!completion.diagnosticAllowed()) {
                timing.lock(); return receipt("TIMING_BLOCKED", 0, false, completion.reason());
            }
            if (!value.tlsVerified()) timing.lock();
            return receipt(value.status(), value.httpStatus(), value.tlsVerified(), value.failureType());
        } catch (RuntimeException failure) {
            timing.lock(); return receipt("TRANSPORT_FAILED", 0, false, "INTERNAL_FAILURE");
        }
    }
}
