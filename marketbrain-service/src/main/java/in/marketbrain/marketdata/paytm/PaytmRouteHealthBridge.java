package in.marketbrain.marketdata.paytm;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.UUID;
import java.util.function.LongSupplier;
import java.util.function.Supplier;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Authenticated diagnostic evidence input. The trusted OS/VPS collector is not yet connected. */
@Component
public final class PaytmRouteHealthBridge {
    private final PaytmApplicationRoute route;
    private final String token, bootId;
    private final boolean enabled;
    private final LongSupplier nano;
    private final Supplier<PaytmGatewayTransport.Observation> probe;
    private String challenge;
    private long issued, sequence;
    private static final long WINDOW = 10_000_000_000L;
    public record Evidence(String challenge, String bootId, boolean synchronizedClock,
                           boolean transportHealthy, double lowerOffsetSeconds, double upperOffsetSeconds) {}
    public record Receipt(String status, String challenge, String bootId, int validForSeconds,
                          boolean accepted, boolean ordersEnabled, String healthContractVersion) {}
    public record ClockReceipt(String clockContractVersion, String bootId, long observedEpochMillis,
                               boolean accepted, boolean ordersEnabled) {}
    /** Read-only clock sample: does not issue/consume a challenge, publish health or arm a route. */
    public ClockReceipt clock() {
        if(!enabled) throw new IllegalStateException("DISABLED");
        return new ClockReceipt("HEALTH_CLOCK_V1",bootId,System.currentTimeMillis(),false,false);
    }
    @Autowired
    public PaytmRouteHealthBridge(PaytmApplicationRoute route,
            @Value("${marketbrain.paytm-money.health-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode,
            @Value("${marketbrain.paper.read-token:}") String readToken) {
        this(route,token,mode,readToken,System::nanoTime,()->{
            try(var transport=new PaytmGatewayTransport("host.docker.internal",18889,Duration.ofSeconds(2))) { return transport.head(); }
        });
    }
    PaytmRouteHealthBridge(PaytmApplicationRoute route,String token,String mode,String readToken,LongSupplier nano,Supplier<PaytmGatewayTransport.Observation> probe) {
        this.route=route;this.token=token;this.nano=nano;this.probe=probe;
        this.enabled="PAPER".equals(mode) && valid(token) && !token.equals(readToken);
        this.bootId=route.status().bootId();
    }
    private static boolean valid(String value) { return value!=null && value.matches("[A-Za-z0-9_-]{32,128}"); }
    public boolean enabled() { return enabled; }
    public boolean authenticates(String supplied) {
        return enabled && valid(supplied) && MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8),supplied.getBytes(StandardCharsets.UTF_8));
    }
    public synchronized Receipt challenge() {
        if(!enabled) return receipt("DISABLED",null,false);
        challenge=UUID.randomUUID().toString();issued=nano.getAsLong();
        return receipt("CHALLENGE",challenge,false);
    }
    public synchronized Receipt submit(Evidence e) {
        if(!enabled) return receipt("DISABLED",null,false);
        long age=nano.getAsLong()-issued;
        boolean matches=e!=null && challenge!=null && challenge.equals(e.challenge()) && bootId.equals(e.bootId()) && age>=0 && age<WINDOW;
        challenge=null; // Every authenticated submission consumes the outstanding challenge.
        if(!matches || sequence==Long.MAX_VALUE) {
            route.observeHealth(null); return receipt("REJECTED_AND_LOCKED",null,false);
        }
        boolean transportHealthy=false;
        boolean credible=e.synchronizedClock() && e.transportHealthy()
            && Double.isFinite(e.lowerOffsetSeconds()) && Double.isFinite(e.upperOffsetSeconds())
            && e.lowerOffsetSeconds()<=e.upperOffsetSeconds() && e.lowerOffsetSeconds()>=-5 && e.upperOffsetSeconds()<=5;
        if(credible) {
            try {
                var observation=probe.get();
                transportHealthy=observation!=null && observation.tlsVerified()
                    && "TLS_RESPONSE".equals(observation.status()) && "NONE".equals(observation.failureType())
                    && observation.httpStatus()>=200 && observation.httpStatus()<=599;
            } catch(RuntimeException ignored) { /* Untrusted transport exception text is never returned. */ }
        }
        age=nano.getAsLong()-issued;
        if(age<0 || age>=WINDOW) { route.observeHealth(null);return receipt("REJECTED_AND_LOCKED",null,false); }
        boolean accepted=route.observeHealth(new PaytmDiagnosticTimingGuard.Health(bootId,sequence++,e.synchronizedClock(),transportHealthy,e.lowerOffsetSeconds(),e.upperOffsetSeconds()));
        return receipt(accepted?"HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED":"UNHEALTHY_AND_LOCKED",null,accepted);
    }
    private Receipt receipt(String status,String nonce,boolean accepted) {
        return new Receipt(status,nonce,bootId,nonce==null?0:10,accepted,false,"SERVER_TRANSPORT_V2");
    }
}
