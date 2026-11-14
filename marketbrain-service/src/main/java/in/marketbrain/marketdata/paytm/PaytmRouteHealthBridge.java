package in.marketbrain.marketdata.paytm;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.UUID;
import java.util.function.LongSupplier;
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
    private String challenge;
    private long issued, sequence;
    private static final long WINDOW = 10_000_000_000L;
    public record Evidence(String challenge, String bootId, boolean synchronizedClock,
                           boolean transportHealthy, double lowerOffsetSeconds, double upperOffsetSeconds) {}
    public record Receipt(String status, String challenge, String bootId, int validForSeconds,
                          boolean accepted, boolean ordersEnabled) {}
    @Autowired
    public PaytmRouteHealthBridge(PaytmApplicationRoute route,
            @Value("${marketbrain.paytm-money.health-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode,
            @Value("${marketbrain.paper.read-token:}") String readToken) {
        this(route,token,mode,readToken,System::nanoTime);
    }
    PaytmRouteHealthBridge(PaytmApplicationRoute route,String token,String mode,String readToken,LongSupplier nano) {
        this.route=route;this.token=token;this.nano=nano;
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
        boolean accepted=route.observeHealth(new PaytmDiagnosticTimingGuard.Health(bootId,sequence++,e.synchronizedClock(),e.transportHealthy(),e.lowerOffsetSeconds(),e.upperOffsetSeconds()));
        return receipt(accepted?"HEALTH_RECORDED_EXPLICIT_ARM_REQUIRED":"UNHEALTHY_AND_LOCKED",null,accepted);
    }
    private Receipt receipt(String status,String nonce,boolean accepted) {
        return new Receipt(status,nonce,bootId,nonce==null?0:10,accepted,false);
    }
}
