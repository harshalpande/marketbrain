package in.marketbrain.paper;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperRestrictedDeliveryTest {
    @Test void restrictedBatchUsesFunctionsAndNeverDirectIssuer()throws Exception {
        var c=mock(Connection.class);when(c.createStatement()).thenReturn(mock(Statement.class));
        var statements=new ArrayList<String>();
        when(c.prepareStatement(anyString())).thenAnswer(call->{String sql=call.getArgument(0);statements.add(sql);var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true);when(r.getString(1)).thenReturn("PENDING");return s;});
        var review=mock(PaperApprovalReview.class);var sender=mock(PaperApprovalDelivery.Sender.class);
        var delivery=PaperApprovalDelivery.restrictedPublisher(()->c,review,sender,Clock.systemUTC(),new byte[32]);
        assertEquals(List.of("PENDING","PENDING"),delivery.enqueueBatch(List.of(PaperDeliveryVerification.proposal("a"),PaperDeliveryVerification.proposal("b"))));
        assertEquals(List.of("SELECT paper_publish_enqueue(?,?,?,?,?,?)","SELECT paper_publish_enqueue(?,?,?,?,?,?)"),statements);
        verify(c).commit();verifyNoInteractions(review,sender);
    }
    @Test void functionDenialRollsBackWithoutSenderOrOwnerFallback()throws Exception {
        var c=mock(Connection.class);when(c.createStatement()).thenReturn(mock(Statement.class));when(c.prepareStatement(anyString())).thenThrow(new SQLException("denied","42501"));
        var review=mock(PaperApprovalReview.class);var sender=mock(PaperApprovalDelivery.Sender.class);
        var delivery=PaperApprovalDelivery.restrictedPublisher(()->c,review,sender,Clock.systemUTC(),new byte[32]);
        assertThrows(SQLException.class,()->delivery.enqueue(PaperDeliveryVerification.proposal("a")));
        verify(c).rollback();verify(c,never()).commit();verifyNoInteractions(review,sender);
    }
    @Test void directWritePrivilegeDriftBlocksPublisher()throws Exception {
        var c=mock(Connection.class);
        when(c.prepareStatement(anyString())).thenAnswer(call->{String sql=call.getArgument(0);var s=mock(PreparedStatement.class);var r=mock(ResultSet.class);when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true);
            when(r.getString(1)).thenReturn(PaperPaytmReviewPublisher.ROLE);when(r.getString(2)).thenReturn(PaperPaytmReviewPublisher.ROLE);
            if(sql.contains("bool_or"))when(r.getBoolean(1)).thenReturn(true);return s;});
        assertEquals("PUBLISHER_DIRECT_WRITE_PRIVILEGE_REJECTED",assertThrows(SQLException.class,()->PaperPaytmReviewPublisher.verifyRole(c)).getMessage());
    }
}
