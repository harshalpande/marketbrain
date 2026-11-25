package in.marketbrain.paper;
import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import java.sql.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static in.marketbrain.paper.PaperApprovalReview.*;

class PaperPaytmReviewPublisherTest {
    static final Instant NOW=Instant.parse("2026-11-25T06:00:00Z");
    static final String ID="a".repeat(32);
    final PaytmPaperReviewAdapter quotes=mock(PaytmPaperReviewAdapter.class);
    final PaperApprovalDelivery delivery=mock(PaperApprovalDelivery.class);
    Connection connection(String failure)throws Exception {
        var c=mock(Connection.class);when(c.createStatement()).thenReturn(mock(Statement.class));
        when(c.prepareStatement(anyString())).thenAnswer(call->{
            String sql=call.getArgument(0);var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);
            when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(!sql.contains("paper_ledger_position"));
            if(sql.contains("telegram_binding")){when(r.getLong(1)).thenReturn(111L);when(r.getLong(2)).thenReturn(222L);if(failure.equals("binding"))when(r.next()).thenReturn(false);}
            if(sql.startsWith("SELECT revision"))when(r.getLong(1)).thenReturn(0L);
            if(sql.startsWith("SELECT current_cash"))when(r.getBigDecimal(1)).thenReturn(new BigDecimal("100000.00"));
            if(sql.startsWith("SELECT cash")){
                when(r.getLong(1)).thenReturn(failure.equals("cash")?1L:10000000L);when(r.getLong(4)).thenReturn(10000000L);when(r.getString(7)).thenReturn("0".repeat(64));
            }
            if(sql.startsWith("SELECT symbol"))when(r.getString(1)).thenReturn("RELIANCE");
            return s;
        });return c;
    }
    PaperPaytmReviewPublisher publisher(Connection c,long price) {
        when(quotes.clock()).thenReturn(Clock.fixed(NOW,ZoneOffset.UTC));
        when(quotes.reference("RELIANCE")).thenReturn(new PaytmPaperReviewAdapter.Reference(
            new MarketQuote(1202,"RELIANCE","PAYTM",price,NOW.minusSeconds(2),NOW),Map.of("symbol","RELIANCE")));
        return new PaperPaytmReviewPublisher(()->c,quotes,delivery);
    }
    @Test void threeCasesUseOneQuoteStoredRecipientAndAtomicDelivery()throws Exception {
        var c=connection("");var p=publisher(c,137560);var plan=p.prepare(ID,1,"RELIANCE");
        assertEquals(3,plan.proposals().size());
        for(var proposal:plan.proposals()){
            assertEquals(111,proposal.userId());assertEquals(222,proposal.chatId());assertEquals(1202,proposal.instrumentId());
            assertEquals(NOW.plusSeconds(100),proposal.terms().expiresAt());assertEquals(1,proposal.terms().quantity());
        }
        when(delivery.enqueueBatch(plan.proposals())).thenReturn(List.of("PENDING","PENDING","PENDING"));
        assertEquals(3,p.enqueue(plan).size());p.dispatch(plan,"ACCEPT");p.dispatch(plan,"REJECT");p.dispatch(plan,"EXPIRE");
        verify(quotes,times(1)).reference("RELIANCE");verify(delivery).enqueueBatch(plan.proposals());verify(c).commit();
        assertThrows(UnsupportedOperationException.class,()->plan.proposals().clear());
        assertThrows(IllegalArgumentException.class,()->p.dispatch(plan,"OTHER"));
    }
    @ParameterizedTest @ValueSource(strings={"binding","cash"})
    void badStoredStateRollsBackAndDoesNotPublish(String failure)throws Exception {
        var c=connection(failure);var p=publisher(c,137560);
        assertThrows(IllegalStateException.class,()->p.prepare(ID,1,"RELIANCE"));verify(c).rollback();verifyNoInteractions(delivery);
    }
    @ParameterizedTest @ValueSource(longs={0,500001,Long.MAX_VALUE})
    void invalidNotionalNeverTouchesStorage(long price)throws Exception {
        var c=connection("");var p=publisher(c,price);assertThrows(IllegalArgumentException.class,()->p.prepare(ID,1,"RELIANCE"));
        verify(c,never()).createStatement();verifyNoInteractions(delivery);
    }
    @Test void quoteBudgetFailureDoesNotPublishOrWrite()throws Exception {
        var c=connection("");var p=publisher(c,137560);when(quotes.reference("RELIANCE")).thenThrow(new IllegalStateException("budget"));
        assertThrows(IllegalStateException.class,()->p.prepare(ID,1,"RELIANCE"));verifyNoInteractions(delivery);verify(c,never()).createStatement();
    }
    @Test void missingCaseOrChangedBatchIdentityCannotDispatch()throws Exception {
        var p=publisher(connection(""),137560);var plan=p.prepare(ID,1,"RELIANCE");
        assertThrows(IllegalArgumentException.class,()->p.enqueue(new PaperPaytmReviewPublisher.Plan(ID,plan.proposals().subList(0,2),plan.identity())));
        assertThrows(IllegalArgumentException.class,()->p.enqueue(new PaperPaytmReviewPublisher.Plan("b".repeat(32),plan.proposals(),plan.identity())));
        verifyNoInteractions(delivery);
    }
    @ParameterizedTest @ValueSource(strings={"wrongRole","owner","superuser","missing"})
    void publisherRoleGuardRejectsAuthorityDrift(String kind)throws Exception {
        var c=mock(Connection.class);var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);
        when(c.prepareStatement(anyString())).thenReturn(s);when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(!kind.equals("missing"));
        when(r.getString(1)).thenReturn(kind.equals("wrongRole")?"postgres":PaperPaytmReviewPublisher.ROLE);when(r.getString(2)).thenReturn(PaperPaytmReviewPublisher.ROLE);
        if(kind.equals("owner"))when(r.getBoolean(8)).thenReturn(true);if(kind.equals("superuser"))when(r.getBoolean(3)).thenReturn(true);
        assertThrows(SQLException.class,()->PaperPaytmReviewPublisher.verifyRole(c));
    }
}
