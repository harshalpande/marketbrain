package in.marketbrain.marketdata.paytm;

import jakarta.annotation.PreDestroy;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

/** Local opt-in PAPER login. Never receives broker passwords/OTP, only app credentials. */
@RestController
@ConditionalOnProperty(name="marketbrain.paytm-supervised.enabled", havingValue="true")
public final class PaytmSupervisedController {
    private static final String COOKIE = "marketbrain_paytm_supervised";
    private final PaytmSupervisedClient client = new PaytmSupervisedClient();
    private final PaytmSupervisedSession session = new PaytmSupervisedSession(client);
    private final String token;
    public PaytmSupervisedController(@Value("${marketbrain.paper.read-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode,
            @Value("${marketbrain.paytm-auth.rehearsal.enabled:false}") boolean rehearsal) {
        if (!"PAPER".equals(mode) || rehearsal || token == null || !token.matches("[A-Za-z0-9_-]{32,128}"))
            throw new IllegalStateException("SUPERVISED_CONFIGURATION_REJECTED");
        this.token = token;
    }
    public record Start(String apiKey, String apiSecret, long vpsEpochMilliseconds) {
        @Override public String toString() { return "SupervisedStart[REDACTED]"; }
    }
    @PostMapping("/api/v1/paytm/supervised/start")
    public ResponseEntity<?> start(@RequestBody Start body, HttpServletRequest request) {
        if (!authorized(request)) return response(401).body(Map.of("status","UNAUTHORIZED"));
        try { return response(200).body(Map.of("browserUrl",session.start(body.apiKey(), body.apiSecret(), body.vpsEpochMilliseconds()),"ordersEnabled",false)); }
        catch (RuntimeException e) { return response(400).body(Map.of("status","SUPERVISED_START_REJECTED")); }
    }
    @PostMapping("/api/v1/paytm/supervised/{command:status|lock}")
    public ResponseEntity<?> command(@PathVariable String command, HttpServletRequest request) {
        if (!authorized(request)) return response(401).body(Map.of("status","UNAUTHORIZED"));
        if ("lock".equals(command)) session.close();
        return response(200).body(session.status());
    }
    public record QuoteRequest(int securityId) { }
    @PostMapping("/api/v1/paytm/supervised/quote")
    public ResponseEntity<?> quote(@RequestBody QuoteRequest body, HttpServletRequest request) {
        if (!authorized(request)) return response(401).body(Map.of("status","UNAUTHORIZED"));
        try { return response(200).body(session.quote(body.securityId())); }
        catch (RuntimeException e) {
            String reason=e.getMessage()!=null && e.getMessage().matches("(PAYTM|SUPERVISED)_[A-Z0-9_]{1,80}")?e.getMessage():"PAYTM_QUOTE_FAILED";
            return response(200).body(Map.of("status",reason,"ordersEnabled",false,"fresh",false,"mappingVerified",false));
        }
    }
    @GetMapping("/paytm/supervised/browser")
    public ResponseEntity<?> browser(@RequestParam String code, HttpServletRequest request) {
        if (!local(request)) return response(400).body("Local browser required.");
        try {
            var start = session.browser(code);
            return response(303).header("Set-Cookie", cookie(start.binding(),600)).location(start.location()).build();
        } catch (RuntimeException e) { return response(400).body("Login session unavailable. Start again locally."); }
    }
    @GetMapping("/paytm/callback")
    public ResponseEntity<?> callback(HttpServletRequest request) {
        if (!local(request)) return response(400).body("Local browser required.");
        try {
            var cookies = request.getCookies();
            var matches = cookies == null ? List.<jakarta.servlet.http.Cookie>of() : Arrays.stream(cookies).filter(c -> COOKIE.equals(c.getName())).toList();
            if (matches.size()!=1) throw new IllegalArgumentException();
            session.callback(request.getQueryString(), matches.getFirst().getValue());
            return response(200).header("Set-Cookie",cookie("",0)).body("Paytm read access verified. No orders enabled. Return to PowerShell.");
        } catch (RuntimeException e) {
            return response(400).header("Set-Cookie",cookie("",0)).body("Paytm login/read check failed. No orders enabled. Return to PowerShell.");
        }
    }
    boolean authorized(HttpServletRequest r) {
        String supplied = r.getHeader("X-MarketBrain-Paper-Read-Token");
        return local(r) && r.getHeader("Origin") == null && r.getQueryString() == null
                && "supervised-paper".equals(r.getHeader("X-MarketBrain-Paytm-Supervised"))
                && supplied != null && MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8), supplied.getBytes(StandardCharsets.UTF_8));
    }
    static boolean local(HttpServletRequest r) {
        // Docker NAT changes remoteAddress. Host port must remain published on 127.0.0.1 only.
        return "127.0.0.1:8080".equals(r.getHeader("Host")) && !r.isSecure()
                && r.getHeader("Forwarded") == null && r.getHeader("X-Forwarded-For") == null
                && r.getHeader("X-Forwarded-Host") == null && r.getHeader("X-Forwarded-Proto") == null;
    }
    private static String cookie(String value, long seconds) {
        return ResponseCookie.from(COOKIE,value).httpOnly(true).sameSite("Lax").path("/paytm").maxAge(seconds).build().toString();
    }
    private static ResponseEntity.BodyBuilder response(int code) {
        return ResponseEntity.status(code).header("Cache-Control","no-store").header("Referrer-Policy","no-referrer")
                .header("Content-Security-Policy","default-src 'none'; frame-ancestors 'none'");
    }
    @PreDestroy void shutdown() { session.close(); client.close(); }
}
