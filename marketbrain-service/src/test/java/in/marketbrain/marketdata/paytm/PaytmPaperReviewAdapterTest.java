package in.marketbrain.marketdata.paytm;
import in.marketbrain.paper.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaytmPaperReviewAdapterTest {
    static final Instant NOW=Instant.parse("2026-11-25T05:00:00Z");
    static PaperApprovalReview.Proposal proposal(String policy,long instrument,Instant expires){
        var a=new PaperAccountEngineering.Approval("p","o","RELIANCE",PaperAccountEngineering.Side.BUY,1,137560,137000,138000,0,NOW.minusSeconds(10),expires);
        return new PaperApprovalReview.Proposal("p",1,instrument,0,111,222,a,policy);
    }
    @ParameterizedTest @ValueSource(strings={"valid","stale","missing","wrongId","instrument","fractionalPaise","textPrice","future","ageLie","quoteBeforeProposal","lateDelivery","expired","expiresDuringFetch","oldPolicy","locked","providerFailure","clockLost"})
    void onlyFreshServerBoundQuoteReachesReview(String mode){
        var guard=mock(PaytmSupervisedController.class);
        when(guard.reviewInstant()).thenReturn(NOW);
        if(mode.equals("locked"))when(guard.reviewInstant()).thenThrow(new IllegalStateException("PRIVATE_DETAIL"));
        if(mode.equals("clockLost"))when(guard.reviewInstant()).thenReturn(NOW).thenThrow(new IllegalStateException("PRIVATE_DETAIL"));
        if(mode.equals("expiresDuringFetch"))when(guard.reviewInstant()).thenReturn(NOW,NOW.plusSeconds(90));
        Map<String,Object> q=new HashMap<>(Map.of("fresh",true,"status","FRESH_QUOTE_OBSERVED","ordersEnabled",false,"securityId",2885,"exchange","NSE","scripType","EQUITY","timestampEpoch","PAYTM_1980_SECONDS","lastPrice",new BigDecimal("1375.60")));
        q.put("tradeEpochMilliseconds",NOW.minusSeconds(1).toEpochMilli());q.put("observedEpochMilliseconds",NOW.toEpochMilli());q.put("ageMilliseconds",1000);
        switch(mode){
            case "stale" -> {q.put("fresh",false);q.put("status","STALE_QUOTE");}
            case "missing" -> {q.put("fresh",false);q.put("status","NO_QUOTE");}
            case "wrongId" -> q.put("securityId",1);
            case "fractionalPaise" -> q.put("lastPrice",new BigDecimal("1375.601"));
            case "textPrice" -> q.put("lastPrice","1375.60");
            case "future" -> q.put("tradeEpochMilliseconds",NOW.plusSeconds(1).toEpochMilli());
            case "ageLie" -> q.put("ageMilliseconds",0);
            case "quoteBeforeProposal" -> q.put("tradeEpochMilliseconds",NOW.minusSeconds(11).toEpochMilli());
            case "lateDelivery" -> q.put("observedEpochMilliseconds",NOW.plusSeconds(1).toEpochMilli());
        }
        when(guard.readBoundQuote(2885)).thenReturn(q);
        if(mode.equals("providerFailure"))when(guard.readBoundQuote(2885)).thenThrow(new IllegalStateException("PRIVATE_DETAIL"));
        var p=proposal(mode.equals("oldPolicy")?PaperReviewTestPolicy.ID:PaperReviewTestPolicy.paytmPolicy().id(),mode.equals("instrument")?2:1,mode.equals("expired")?NOW:NOW.plusSeconds(90));
        try(var adapter=new PaytmPaperReviewAdapter(guard,new PaytmUniverseMatch(s->List.of(PaytmUniverseMatchTest.row())),PaytmReviewIdentityTest.source(PaytmReviewIdentityTest.master(),PaytmReviewIdentityTest.members()))){
            if(mode.equals("valid")){
                var quote=adapter.latest(p);assertThat(quote.provider()).isEqualTo("PAYTM");assertThat(quote.pricePaise()).isEqualTo(137560);assertThat(quote.instrumentId()).isEqualTo(1);
                adapter.latest(p);verify(guard,times(2)).readBoundQuote(2885); // no cached quote reused
            }else assertThatThrownBy(()->adapter.latest(p)).hasMessage("PAYTM_REVIEW_QUOTE_UNAVAILABLE").hasNoCause();
            if(Set.of("instrument","expired","oldPolicy","locked").contains(mode))verify(guard,never()).readBoundQuote(anyInt());
        }
    }
    @Test void limitsStayExactAndPreviousPolicyRemainsUnchanged(){
        var p=PaperReviewTestPolicy.paytmPolicy();assertThat(p.provider()).isEqualTo("PAYTM");assertThat(p.maxProposalLifetime()).isEqualTo(Duration.ofSeconds(100));
        assertThat(p.limits()).isEqualTo(new PaperAccountEngineering.Policy(15000,50,1,500000,2,1));
        assertThat(PaperReviewTestPolicy.policy().provider()).isEqualTo("UPSTOX");assertThatThrownBy(()->PaperReviewTestPolicy.requireExact(p)).isInstanceOf(IllegalArgumentException.class);
    }
}
