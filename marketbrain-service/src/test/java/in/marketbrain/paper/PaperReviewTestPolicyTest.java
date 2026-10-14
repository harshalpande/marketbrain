package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;

class PaperReviewTestPolicyTest {
    final Instant t = Instant.parse("2026-10-15T04:00:00Z");
    Proposal proposal(long quantity, long reference, long max) {
        return new Proposal("test",1,1,0,1,1,new Approval("test","order","TEST",Side.BUY,quantity,
                reference,reference,max,0,t,t.plusSeconds(100)),PaperReviewTestPolicy.ID);
    }
    String evaluate(Proposal p, Instant now, long price, Instant observed) {
        return PaperApprovalReview.evaluate(p,new MarketQuote(1,"TEST","UPSTOX",price,observed,now),
                new Snapshot(0,10000000,0,0,0,true),now,PaperReviewTestPolicy.policy());
    }
    @Test void exactOwnerPolicyAndPaiseConversion() {
        var p=PaperReviewTestPolicy.policy();
        assertEquals(Duration.ofSeconds(100),p.maxProposalLifetime());assertEquals(15000,p.limits().maxQuoteAgeMillis());
        assertEquals(50,p.limits().maxSlippageBps());assertEquals(1,p.limits().maxQuantity());
        assertEquals(500000,p.limits().maxOrderNotionalPaise());
        PaperReviewTestPolicy.requireExact(p);
        assertThrows(IllegalArgumentException.class,()->PaperReviewTestPolicy.requireExact(PaperApprovalVerification.POLICY));
    }
    @Test void quoteAgeBoundaryIsInclusiveButOneMillisecondOlderIsBlocked() {
        var p=proposal(1,10000,10050); var now=t.plusSeconds(20);
        assertEquals("ACCEPTED_EXECUTION_BLOCKED",evaluate(p,now,10000,now.minusSeconds(15)));
        assertEquals("QUOTE_TIME_INVALID",evaluate(p,now,10000,now.minusMillis(15001)));
    }
    @Test void expiresAtExactly100Seconds() {
        var p=proposal(1,10000,10050);
        assertEquals("ACCEPTED_EXECUTION_BLOCKED",evaluate(p,t.plusSeconds(99),10000,t.plusSeconds(99)));
        assertEquals("EXPIRED",evaluate(p,t.plusSeconds(100),10000,t.plusSeconds(100)));
    }
    @Test void notionalUsesWorstAllowedZoneNotOnlyCurrentQuote() {
        assertEquals("ACCEPTED_EXECUTION_BLOCKED",evaluate(proposal(1,499000,500000),t,499000,t));
        assertEquals("RISK_BLOCKED",evaluate(proposal(1,499000,500001),t,499000,t));
    }
    @Test void quantityAndSlippageCannotBeLoosenedByFreshQuote() {
        assertEquals("RISK_BLOCKED",evaluate(proposal(2,10000,10050),t,10000,t));
        assertEquals("ACCEPTED_EXECUTION_BLOCKED",evaluate(proposal(1,10000,10100),t,10050,t));
        assertEquals("RISK_BLOCKED",evaluate(proposal(1,10000,10100),t,10051,t));
    }
    @Test void noHoldOrSellExecutionAuthorityIsIntroduced() {
        var p=proposal(1,10000,10050);
        var sell=new Proposal(p.id(),1,1,0,1,1,new Approval("test","order","TEST",Side.SELL,1,10000,10000,10050,0,t,t.plusSeconds(100)),p.policyId());
        assertEquals("INSUFFICIENT_SHARES",evaluate(sell,t,10000,t));
    }
}
