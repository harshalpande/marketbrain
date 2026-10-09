package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperApprovalVerification.POLICY;
import static in.marketbrain.paper.PaperApprovalVerification.proposal;
import static in.marketbrain.paper.PaperApprovalVerification.quote;

/** No database/model/provider runtime. Transaction/concurrency acceptance remains the spare suite. */
class PaperApprovalReviewTest {
    private final Snapshot account=new Snapshot(0,10000000,0,10,0,true);
    private final Proposal buy=proposal("p",Side.BUY,10,0);
    private String assess(Proposal p,MarketQuote q,Snapshot s,Instant at,PolicyVersion policy){return PaperApprovalReview.evaluate(p,q,s,at,policy);}
    @Test void validBuyIsReviewOnly(){assertEquals("ACCEPTED_EXECUTION_BLOCKED",assess(buy,quote(),account,T,POLICY));}
    @Test void validOwnedSellIsReviewOnly(){assertEquals("ACCEPTED_EXECUTION_BLOCKED",assess(proposal("s",Side.SELL,10,0),quote(),account,T,POLICY));}
    @Test void changedRevisionBlocks(){assertEquals("ACCOUNT_CHANGED",assess(buy,quote(),new Snapshot(1,10000000,0,0,0,true),T,POLICY));}
    @Test void corruptionBlocks(){assertEquals("ACCOUNT_INCONSISTENT",assess(buy,quote(),new Snapshot(0,10000000,0,0,0,false),T,POLICY));}
    @Test void missingQuoteBlocks(){assertEquals("QUOTE_UNAVAILABLE",assess(buy,null,account,T,POLICY));}
    @Test void expiredAtExactBoundary(){assertEquals("EXPIRED",assess(buy,quote(),account,T.plusSeconds(120),POLICY));}
    @Test void futureProposalBlocks(){assertEquals("CLOCK_INVALID",assess(buy,quote(),account,T.minusNanos(1),POLICY));}
    @Test void changedPolicyIdBlocks(){assertEquals("POLICY_CHANGED",assess(buy,quote(),account,T,new PolicyVersion("OTHER","FIXTURE",fixturePolicy(),Duration.ofMinutes(2))));}
    @ParameterizedTest @ValueSource(strings={"instrument","symbol","provider"})
    void wrongQuoteIdentity(String field){var q=new MarketQuote(field.equals("instrument")?2:1,field.equals("symbol")?"OTHER":"FIXTURE",field.equals("provider")?"OTHER":"FIXTURE",10000,T,T);assertEquals("QUOTE_IDENTITY_MISMATCH",assess(buy,q,account,T,POLICY));}
    @ParameterizedTest @ValueSource(strings={"old","future","receivedFuture","observedAfterReceived","missingObserved","missingReceived","zeroPrice"})
    void invalidQuoteEvidence(String kind){Instant observed=T,received=T;
        switch(kind){case "old"->observed=T.minusSeconds(1);case "future"->{observed=T.plusSeconds(1);received=observed;}case "receivedFuture"->received=T.plusSeconds(1);case "observedAfterReceived"->received=T.minusSeconds(1);case "missingObserved"->observed=null;case "missingReceived"->received=null;}
        assertEquals("QUOTE_TIME_INVALID",assess(buy,new MarketQuote(1,"FIXTURE","FIXTURE",kind.equals("zeroPrice")?0:10000,observed,received),account,T,POLICY));}
    @Test void quoteFreshnessBoundary(){assertEquals("ACCEPTED_EXECUTION_BLOCKED",assess(buy,quote(),account,T.plusMillis(5000),POLICY));assertEquals("QUOTE_TIME_INVALID",assess(buy,quote(),account,T.plusMillis(5000).plusNanos(1),POLICY));}
    @ParameterizedTest @ValueSource(longs={9899,10101})
    void outsideZoneBlocks(long price){assertEquals("RISK_BLOCKED",assess(buy,new MarketQuote(1,"FIXTURE","FIXTURE",price,T,T),account,T,POLICY));}
    @Test void slippageHasIndependentLimit(){var policy=new PolicyVersion("FIXTURE_V1","FIXTURE",new Policy(5000,10,10000,10000000,50,100),Duration.ofMinutes(2));assertEquals("RISK_BLOCKED",assess(buy,new MarketQuote(1,"FIXTURE","FIXTURE",10099,T,T),account,T,policy));}
    @Test void cashIncludesReservationAndFee(){assertEquals("INSUFFICIENT_CASH",assess(buy,quote(),new Snapshot(0,101100,1,0,0,true),T,POLICY));assertEquals("ACCEPTED_EXECUTION_BLOCKED",assess(buy,quote(),new Snapshot(0,101100,0,0,0,true),T,POLICY));}
    @Test void sharesExcludeOtherReservations(){assertEquals("INSUFFICIENT_SHARES",assess(proposal("s",Side.SELL,10,0),quote(),new Snapshot(0,10000000,0,10,1,true),T,POLICY));}
    @Test void orderNotionalLimitBlocks(){assertEquals("RISK_BLOCKED",assess(proposal("p",Side.BUY,1000,0),quote(),account,T,POLICY));}
    @Test void quantityLimitBlocks(){var policy=new PolicyVersion("FIXTURE_V1","FIXTURE",new Policy(5000,200,9,10000000,50,100),Duration.ofMinutes(2));assertEquals("RISK_BLOCKED",assess(buy,quote(),account,T,policy));}
    @Test void arithmeticOverflowCannotAccept(){assertEquals("RISK_BLOCKED",assess(proposal("p",Side.BUY,Long.MAX_VALUE,0),quote(),account,T,POLICY));}
    @Test void privateChatRequiredBeforeAnyIo(){var review=new PaperApprovalReview(()->{throw new AssertionError("DB accessed");},p->{throw new AssertionError("Quote accessed");},Clock.fixed(T,ZoneOffset.UTC),POLICY);assertThrows(IllegalArgumentException.class,()->review.process(new Callback("id",111,222,false,"a".repeat(43))));}
    @Test void holdAndExpiredIssueRejectedBeforeDatabase(){var review=new PaperApprovalReview(()->{throw new AssertionError("DB accessed");},p->quote(),Clock.fixed(T,ZoneOffset.UTC),POLICY);assertThrows(IllegalArgumentException.class,()->review.issue(proposal("h",Side.HOLD,0,0)));var expired=new PaperApprovalReview(()->{throw new AssertionError("DB accessed");},p->quote(),Clock.fixed(T.plusSeconds(120),ZoneOffset.UTC),POLICY);assertThrows(IllegalArgumentException.class,()->expired.issue(buy));}
    @Test void tokenAndIdentityContracts(){assertThrows(IllegalArgumentException.class,()->new Callback("id",111,222,true,"short"));assertThrows(IllegalArgumentException.class,()->new Proposal("other",1,1,0,111,222,buy.terms(),POLICY.id()));assertEquals(64,PaperApprovalReview.identity(111,222).length());assertNotEquals(PaperApprovalReview.identity(111,222),PaperApprovalReview.identity(112,222));}
    @Test void boundedLifetimeRequired(){assertThrows(IllegalArgumentException.class,()->new PolicyVersion("id","fixture",fixturePolicy(),Duration.ofMinutes(11)));assertThrows(IllegalArgumentException.class,()->new PolicyVersion("id","fixture",fixturePolicy(),Duration.ZERO));}
    @Test void persistedRecordsRoundTrip(){
        assertEquals(buy,PaperLedgerStore.decode(PaperPersistenceEngineering.encode(buy),Proposal.class));
        assertEquals(POLICY,PaperLedgerStore.decode(PaperPersistenceEngineering.encode(POLICY),PolicyVersion.class));
        var receipt=new Receipt(PaperApprovalReview.VERSION,"ACCEPTED_EXECUTION_BLOCKED","p",0,POLICY.id(),T,"a".repeat(64),false);
        assertEquals(receipt,PaperLedgerStore.decode(PaperPersistenceEngineering.encode(receipt),Receipt.class));
    }
    @Test void unauthorizedBindingRollsBackBeforeQuote()throws Exception{
        var c=org.mockito.Mockito.mock(java.sql.Connection.class);var setup=org.mockito.Mockito.mock(java.sql.Statement.class);
        var statement=org.mockito.Mockito.mock(java.sql.PreparedStatement.class);var rows=org.mockito.Mockito.mock(java.sql.ResultSet.class);
        org.mockito.Mockito.when(c.createStatement()).thenReturn(setup);org.mockito.Mockito.when(c.prepareStatement(org.mockito.ArgumentMatchers.anyString())).thenReturn(statement);
        org.mockito.Mockito.when(statement.executeQuery()).thenReturn(rows);org.mockito.Mockito.when(rows.next()).thenReturn(false);
        var review=new PaperApprovalReview(()->c,p->{throw new AssertionError("Unauthorized quote access");},Clock.fixed(T,ZoneOffset.UTC),POLICY);
        assertThrows(IllegalArgumentException.class,()->review.process(new Callback("id",111,222,true,"a".repeat(43))));
        org.mockito.Mockito.verify(c).rollback();org.mockito.Mockito.verify(c).close();org.mockito.Mockito.verify(c,org.mockito.Mockito.never()).commit();
        org.mockito.Mockito.verify(statement).setQueryTimeout(10);
    }
    @Test void candidateHasNoSpringOrRuntimeMigration()throws Exception{
        assertEquals(0,PaperApprovalReview.class.getAnnotations().length);
        String sql=PaperLedgerVerification.resource("/paper/approval-v1.sql");assertTrue(sql.contains("NOT a Flyway migration"));assertTrue(sql.contains("UNIQUE (proposal_id,action)"));assertTrue(sql.contains("OLD.receipt IS NOT NULL"));assertTrue(sql.contains("NEW.policy_hash"));
        assertNull(getClass().getResource("/db/migration/V28__paper_approval.sql"));
    }
}
