package in.marketbrain.paper;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

class PaperDeliveryBatchTest {
    @Test void durableReplayUsesOneTransactionAndCallerOrder()throws Exception {
        var a=PaperDeliveryVerification.proposal("a");var b=PaperDeliveryVerification.proposal("b");
        var c=mock(Connection.class);when(c.createStatement()).thenReturn(mock(Statement.class));
        when(c.prepareStatement(anyString())).thenAnswer(call->{
            var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);String sql=call.getArgument(0);
            when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true);when(r.getLong(1)).thenReturn(111L);when(r.getLong(2)).thenReturn(222L);
            if(sql.startsWith("SELECT p.payload"))doAnswer(arg->{String id=arg.getArgument(1);when(r.getString(1)).thenReturn(encode(id.equals("a")?a:b));when(r.getString(2)).thenReturn(id.equals("a")?"SENT":"UNCERTAIN");return null;}).when(s).setObject(eq(1),any());
            return s;
        });
        var review=mock(PaperApprovalReview.class);var sender=mock(PaperApprovalDelivery.Sender.class);
        var d=new PaperApprovalDelivery(()->c,review,sender,Clock.systemUTC(),new byte[32]);
        assertEquals(List.of("UNCERTAIN","SENT"),d.enqueueBatch(List.of(b,a)));verify(c,times(1)).commit();verify(c,never()).rollback();verifyNoInteractions(review,sender);
        assertThrows(IllegalArgumentException.class,()->d.enqueueBatch(List.of(a,a)));
        assertThrows(IllegalArgumentException.class,()->d.enqueueBatch(List.of()));
    }
    @Test void laterEnqueueFailureRollsBackWholeBatch()throws Exception {
        var c=mock(Connection.class);when(c.createStatement()).thenReturn(mock(Statement.class));
        when(c.prepareStatement(anyString())).thenAnswer(call->{var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);when(s.executeQuery()).thenReturn(r);
            when(r.next()).thenReturn(false);if(((String)call.getArgument(0)).contains("telegram_binding")){when(r.next()).thenReturn(true);when(r.getLong(1)).thenReturn(111L);when(r.getLong(2)).thenReturn(222L);}return s;});
        var review=mock(PaperApprovalReview.class);when(review.issue(eq(c),any())).thenReturn(new PaperApprovalReview.Tokens("a".repeat(43),"b".repeat(43))).thenThrow(new SQLException("fixture"));
        var d=new PaperApprovalDelivery(()->c,review,(p,t)->{throw new AssertionError();},Clock.systemUTC(),new byte[32]);
        assertThrows(SQLException.class,()->d.enqueueBatch(List.of(PaperDeliveryVerification.proposal("a"),PaperDeliveryVerification.proposal("b"))));
        verify(c).rollback();verify(c,never()).commit();
    }
}
