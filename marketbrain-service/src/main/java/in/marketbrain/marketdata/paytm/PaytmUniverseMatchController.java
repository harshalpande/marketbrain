package in.marketbrain.marketdata.paytm;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@ConditionalOnProperty(name="marketbrain.paytm-supervised.enabled",havingValue="true")
public final class PaytmUniverseMatchController {
    private final PaytmSupervisedController guard;
    private final PaytmUniverseMatch matcher;
    private final PaytmReviewIdentity identity;
    @org.springframework.beans.factory.annotation.Autowired
    public PaytmUniverseMatchController(PaytmSupervisedController guard,JdbcTemplate jdbc){this(guard,new PaytmUniverseMatch(jdbc),new PaytmReviewIdentity());}
    PaytmUniverseMatchController(PaytmSupervisedController guard,PaytmUniverseMatch matcher,PaytmReviewIdentity identity){this.guard=guard;this.matcher=matcher;this.identity=identity;}
    public record Request(String symbol) { }
    @PostMapping("/api/v1/paytm/supervised/universe-match")
    public ResponseEntity<?> inspect(@RequestBody Request body,HttpServletRequest request){
        var response=ResponseEntity.status(guard.authorized(request)?200:401).header("Cache-Control","no-store");
        if(!guard.authorized(request))return response.body(Map.of("status","UNAUTHORIZED"));
        try{return response.body(matcher.inspect(body.symbol()));}
        catch(Exception e){return response.body(Map.of("status","LOCAL_UNIVERSE_REVIEW_REQUIRED","snapshotMatched",false,"ordersEnabled",false));}
    }
    @PostMapping("/api/v1/paytm/supervised/review-quote")
    public ResponseEntity<?> reviewQuote(@RequestBody Request body,HttpServletRequest request){
        var response=ResponseEntity.status(guard.authorized(request)?200:401).header("Cache-Control","no-store");
        if(!guard.authorized(request))return response.body(Map.of("status","UNAUTHORIZED"));
        try{
            if(!guard.hasReadSession())throw new IllegalStateException("SUPERVISED_SESSION_LOCKED");
            var bound=identity.resolve(body.symbol(),matcher.inspect(body.symbol()));
            var quote=guard.readBoundQuote(bound.securityId());
            boolean fresh=Boolean.TRUE.equals(quote.get("fresh")) && "FRESH_QUOTE_OBSERVED".equals(quote.get("status"));
            return response.body(Map.of("status",fresh?"IDENTITY_BOUND_FRESH_QUOTE":"IDENTITY_BOUND_QUOTE_REJECTED",
                "reviewEligible",fresh,"ordersEnabled",false,"identity",bound.evidence(),"quote",quote));
        }catch(Exception e){
            String reason=e.getMessage()!=null && e.getMessage().matches("(PAYTM|SUPERVISED)_[A-Z0-9_]{1,80}")?e.getMessage():"PAYTM_REVIEW_QUOTE_FAILED";
            return response.body(Map.of("status",reason,"reviewEligible",false,"ordersEnabled",false));
        }
    }
    @jakarta.annotation.PreDestroy void shutdown(){identity.close();}
}
