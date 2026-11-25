package in.marketbrain.paper;
import java.time.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.assertj.core.api.Assertions.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;

class PaperPaytmReviewPolicyTest {
    @ParameterizedTest @ValueSource(strings={"valid","quantity","notional","slippage","zone","expired","stale","wrongProvider","revision","cash","future"})
    void approvedPaytmLimitsRemainReviewOnly(String scenario){
        var policy=PaperReviewTestPolicy.paytmPolicy();Instant start=Instant.parse("2026-11-25T05:00:00Z"),now=start.plusSeconds(20);
        long reference=scenario.equals("notional")?500001:10000;
        var a=new Approval("p","o","RELIANCE",Side.BUY,scenario.equals("quantity")?2:1,reference,reference-100,reference+100,0,start,start.plusSeconds(100));
        var p=new Proposal("p",1,1,0,111,222,a,policy.id());
        var account=new Snapshot(scenario.equals("revision")?1:0,scenario.equals("cash")?0:10000000,0,0,0,true);
        Instant trade=scenario.equals("stale")?now.minusSeconds(16):scenario.equals("future")?now.plusSeconds(1):now;
        long price=scenario.equals("slippage")?10051:scenario.equals("zone")?10101:reference;
        var quote=new MarketQuote(1,"RELIANCE",scenario.equals("wrongProvider")?"UPSTOX":"PAYTM",price,trade,now);
        String expected=switch(scenario){
            case "valid"->"ACCEPTED_EXECUTION_BLOCKED";
            case "expired"->"EXPIRED";
            case "stale","future"->"QUOTE_TIME_INVALID";
            case "wrongProvider"->"QUOTE_IDENTITY_MISMATCH";
            case "revision"->"ACCOUNT_CHANGED";
            case "cash"->"INSUFFICIENT_CASH";
            default->"RISK_BLOCKED";
        };
        assertThat(PaperApprovalReview.evaluate(p,quote,account,scenario.equals("expired")?start.plusSeconds(100):now,policy)).isEqualTo(expected);
    }
}
