package in.marketbrain.marketdata.paytm;

import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/** Uses local paper READ authority only for a fixed credential-free diagnostic, never broker actions. */
@RestController
public final class PaytmApplicationRouteController {
    private final PaytmApplicationRoute route;
    private final String token;
    private final String mode;
    public PaytmApplicationRouteController(PaytmApplicationRoute route,
            @Value("${marketbrain.paper.read-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode) {
        this.route = route; this.token = token; this.mode = mode;
    }
    @PostMapping("/api/v1/paytm/route/{command}")
    public ResponseEntity<?> command(@PathVariable String command, HttpServletRequest request) {
        String supplied = request.getHeader("X-MarketBrain-Paper-Read-Token");
        if (!"PAPER".equals(mode) || !valid(token)) return response(503, "DISABLED");
        if (!valid(supplied) || !MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8),
                supplied.getBytes(StandardCharsets.UTF_8))) return response(401, "UNAUTHORIZED");
        // No browser-origin action, forwarded authority or arbitrary target/header/body accepted.
        if (!"credential-free".equals(request.getHeader("X-MarketBrain-Paytm-Route"))
                || !"127.0.0.1:8080".equals(request.getHeader("Host")) || request.isSecure()
                || request.getHeader("Origin") != null || request.getHeader("Forwarded") != null
                || request.getHeader("X-Forwarded-For") != null || request.getHeader("X-Forwarded-Host") != null
                || request.getQueryString() != null || request.getContentLengthLong() > 0
                || request.getHeader("Transfer-Encoding") != null) return response(400, "REJECTED");
        return switch (command) {
            case "status" -> response(200, route.status());
            case "arm" -> response(200, route.arm());
            case "lock" -> response(200, route.lock());
            case "head" -> response(200, route.head());
            default -> response(400, "REJECTED");
        };
    }
    private static boolean valid(String value) { return value != null && value.matches("[A-Za-z0-9_-]{32,128}"); }
    private static ResponseEntity<?> response(int status, Object body) {
        return ResponseEntity.status(status).header("Cache-Control", "no-store").body(body);
    }
}
