package in.marketbrain.marketdata.paytm;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Set;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/** Bounded authenticated input; never accepts broker destinations or execution commands. */
@RestController
public final class PaytmRouteHealthController {
    private final PaytmRouteHealthBridge bridge;
    private final ObjectMapper json = new ObjectMapper()
        .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
        .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
    private static final Set<String> FIELDS=Set.of("challenge","bootId","synchronizedClock",
        "transportHealthy","lowerOffsetSeconds","upperOffsetSeconds");
    public PaytmRouteHealthController(PaytmRouteHealthBridge bridge) {this.bridge=bridge;}
    @PostMapping("/api/v1/paytm/route-health/{command}")
    public ResponseEntity<?> command(@PathVariable String command, HttpServletRequest request) {
        // Authenticate before reading or parsing a body. Never log credentials or payloads.
        if(!bridge.enabled()) return response(503,"DISABLED");
        if(!bridge.authenticates(request.getHeader("X-MarketBrain-Paytm-Health-Token"))) return response(401,"UNAUTHORIZED");
        if(!"127.0.0.1:8080".equals(request.getHeader("Host")) || request.isSecure()
                || !"diagnostic-health".equals(request.getHeader("X-MarketBrain-Paytm-Health"))
                || request.getQueryString()!=null || request.getHeader("Origin")!=null
                || request.getHeader("Forwarded")!=null || request.getHeader("X-Forwarded-For")!=null
                || request.getHeader("X-Forwarded-Host")!=null || request.getHeader("Transfer-Encoding")!=null
                || request.getContentLengthLong()>2048) return response(400,"REJECTED");
        try {
            if("challenge".equals(command)) {
                if(request.getContentLengthLong()>0 || request.getInputStream().read()!=-1) return response(400,"REJECTED");
                return response(200,bridge.challenge());
            }
            if(!"submit".equals(command) || request.getContentLengthLong()<1
                || request.getContentType()==null
                || !request.getContentType().split(";",2)[0].trim().equalsIgnoreCase("application/json")) return response(400,"REJECTED");
            byte[] bytes=request.getInputStream().readNBytes(2049);
            if(bytes.length>2048 || bytes.length!=request.getContentLengthLong()) return response(400,"REJECTED");
            var node=json.readTree(bytes);
            if(!node.isObject() || node.size()!=FIELDS.size()) return response(400,"REJECTED");
            for(String field:FIELDS) if(!node.hasNonNull(field)) return response(400,"REJECTED");
            if(!node.get("challenge").isTextual() || !node.get("bootId").isTextual()
                || !node.get("synchronizedClock").isBoolean() || !node.get("transportHealthy").isBoolean()
                || !node.get("lowerOffsetSeconds").isNumber() || !node.get("upperOffsetSeconds").isNumber()) return response(400,"REJECTED");
            var evidence=json.treeToValue(node,PaytmRouteHealthBridge.Evidence.class);
            return response(200,bridge.submit(evidence));
        } catch(Exception ignored) { return response(400,"REJECTED"); }
    }
    private static ResponseEntity<?> response(int code,Object value) {return ResponseEntity.status(code).header("Cache-Control","no-store").body(value);}
}
