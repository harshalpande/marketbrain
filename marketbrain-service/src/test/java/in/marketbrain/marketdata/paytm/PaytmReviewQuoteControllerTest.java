package in.marketbrain.marketdata.paytm;
import java.util.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.mockito.Mockito.*;

class PaytmReviewQuoteControllerTest {
    @ParameterizedTest @ValueSource(strings={"fresh","stale","missing","malformed","unauthorized","locked","identityMismatch","transport"})
    void onlyServerBoundFreshQuoteCanBeReviewEligible(String mode)throws Exception{
        var guard=mock(PaytmSupervisedController.class);
        when(guard.authorized(any())).thenReturn(!mode.equals("unauthorized"));
        when(guard.hasReadSession()).thenReturn(!mode.equals("locked"));
        String status=switch(mode){case "stale"->"STALE_QUOTE";case "missing"->"NO_QUOTE";case "malformed"->"MALFORMED_QUOTE";default->"FRESH_QUOTE_OBSERVED";};
        when(guard.readBoundQuote(2885)).thenReturn(Map.of("status",status,"fresh",mode.equals("fresh"),"ordersEnabled",false));
        if(mode.equals("transport"))when(guard.readBoundQuote(2885)).thenThrow(new IllegalStateException("PAYTM_TRANSPORT_OR_JSON_FAILED"));
        var match=new PaytmUniverseMatch(s->mode.equals("identityMismatch")?List.of():List.of(PaytmUniverseMatchTest.row()));
        var controller=new PaytmUniverseMatchController(guard,match,PaytmReviewIdentityTest.source(PaytmReviewIdentityTest.master(),PaytmReviewIdentityTest.members()));
        try{
            var mvc=MockMvcBuilders.standaloneSetup(controller).build();
            var request=post("/api/v1/paytm/supervised/review-quote").contentType("application/json")
                .content("{\"symbol\":\"RELIANCE\",\"securityId\":1,\"fresh\":true,\"lastPrice\":999}");
            if(mode.equals("unauthorized"))mvc.perform(request).andExpect(status().isUnauthorized());
            else mvc.perform(request).andExpect(status().isOk()).andExpect(header().string("Cache-Control","no-store"))
                .andExpect(jsonPath("$.reviewEligible").value(mode.equals("fresh"))).andExpect(jsonPath("$.ordersEnabled").value(false));
            verify(guard,never()).readBoundQuote(1);
            if(Set.of("unauthorized","locked","identityMismatch").contains(mode))verify(guard,never()).readBoundQuote(anyInt());
            else verify(guard).readBoundQuote(2885);
        }finally{controller.shutdown();}
    }
}
