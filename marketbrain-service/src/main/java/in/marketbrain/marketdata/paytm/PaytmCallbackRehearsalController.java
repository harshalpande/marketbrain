package in.marketbrain.marketdata.paytm;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Clock;
import java.util.Arrays;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Synthetic-only, disabled by default. This is NOT an authentication/token-exchange endpoint. */
@RestController
@ConditionalOnProperty(name = "marketbrain.paytm-auth.rehearsal.enabled", havingValue = "true")
public final class PaytmCallbackRehearsalController {
    private static final String COOKIE = "marketbrain_paytm_rehearsal";
    private static final String SYNTHETIC_TOKEN = "SYNTHETIC_REHEARSAL_ONLY";
    private final PaytmLoginPreparation preparation = new PaytmLoginPreparation(Clock.systemUTC());

    @PostMapping("/paytm/rehearsal/start")
    public ResponseEntity<Map<String, Object>> start(HttpServletRequest request) {
        if (!local(request) || !"http://127.0.0.1:8080".equals(request.getHeader("Origin"))
                || !"synthetic-only".equals(request.getHeader("X-MarketBrain-Rehearsal"))) return rejected();
        try {
            var challenge = preparation.begin();
            return response(200).header("Set-Cookie", cookie(challenge.browserBinding(), 600))
                    .body(Map.of("status", "SYNTHETIC_ONLY_NOT_AUTHENTICATED", "callback", PaytmLoginPreparation.CALLBACK
                            + "?state=" + challenge.state() + "&requestToken=" + SYNTHETIC_TOKEN,
                            "expiresAt", challenge.expiresAt().toString(), "authenticated", false));
        } catch (IllegalArgumentException e) { return rejected(); }
    }

    @GetMapping("/paytm/callback")
    public ResponseEntity<Map<String, Object>> callback(HttpServletRequest request) {
        if (!local(request)) return rejected();
        try {
            // Never accept real broker tokens through the synthetic rehearsal surface.
            if (!SYNTHETIC_TOKEN.equals(PaytmLoginPreparation.parse(request.getQueryString()).get("requestToken")))
                return rejected();
            Cookie[] cookies = request.getCookies();
            var matching = cookies == null ? new Cookie[0] : Arrays.stream(cookies)
                    .filter(c -> COOKIE.equals(c.getName())).toArray(Cookie[]::new);
            if (matching.length != 1) return rejected();
            preparation.validateAndDiscard(request.getQueryString(), matching[0].getValue());
            return response(200).header("Set-Cookie", cookie("", 0)).body(Map.of(
                    "status", "SYNTHETIC_CALLBACK_PASSED_REAL_LOGIN_BLOCKED", "authenticated", false));
        } catch (IllegalArgumentException e) { return rejected(); }
    }

    private static boolean local(HttpServletRequest request) {
        // No X-Forwarded-* trust. Docker/proxy deployment requires a separate reviewed ingress design.
        return "127.0.0.1".equals(request.getRemoteAddr()) && "127.0.0.1:8080".equals(request.getHeader("Host"))
                && !request.isSecure() && request.getHeader("Forwarded") == null
                && request.getHeader("X-Forwarded-For") == null && request.getHeader("X-Forwarded-Host") == null;
    }
    private static String cookie(String value, int age) {
        // HTTP is permitted only for this exact loopback rehearsal; no domain attribute.
        return ResponseCookie.from(COOKIE, value).httpOnly(true).sameSite("Lax")
                .path("/paytm").maxAge(age).build().toString();
    }
    private static ResponseEntity.BodyBuilder response(int code) {
        return ResponseEntity.status(code).header("Cache-Control", "no-store")
                .header("Pragma", "no-cache").header("Referrer-Policy", "no-referrer")
                .header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
    }
    private static ResponseEntity<Map<String, Object>> rejected() {
        return response(400).body(Map.of("status", "PAYTM_CALLBACK_REJECTED", "authenticated", false));
    }
}
