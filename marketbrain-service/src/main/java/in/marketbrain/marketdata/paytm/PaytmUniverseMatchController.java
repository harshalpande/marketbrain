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
    public PaytmUniverseMatchController(PaytmSupervisedController guard,JdbcTemplate jdbc){this.guard=guard;matcher=new PaytmUniverseMatch(jdbc);}
    public record Request(String symbol) { }
    @PostMapping("/api/v1/paytm/supervised/universe-match")
    public ResponseEntity<?> inspect(@RequestBody Request body,HttpServletRequest request){
        var response=ResponseEntity.status(guard.authorized(request)?200:401).header("Cache-Control","no-store");
        if(!guard.authorized(request))return response.body(Map.of("status","UNAUTHORIZED"));
        try{return response.body(matcher.inspect(body.symbol()));}
        catch(Exception e){return response.body(Map.of("status","LOCAL_UNIVERSE_REVIEW_REQUIRED","snapshotMatched",false,"ordersEnabled",false));}
    }
}
