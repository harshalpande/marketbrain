package in.marketbrain.paper;

import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.sql.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPublisherRuntimeTest {
    @Test void publisherControlRequiresExplicitFixedTarget() {
        assertEquals(PaperRuntimeControl.SOCKET,PaperRuntimeControl.controlSocket(new String[]{"STATUS"}));
        assertEquals(PaperRuntimeControl.PUBLISHER_SOCKET,PaperRuntimeControl.controlSocket(new String[]{"STATUS","--publisher"}));
        assertThrows(IllegalArgumentException.class,()->PaperRuntimeControl.controlSocket(new String[]{"STATUS","/tmp/other"}));
    }
    final PaperWriterConnector.Target target=new PaperWriterConnector.Target("localhost",5432,"marketbrain",42,PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null);
    @Test void lockedRuntimeNeverReadsKeyOrQuotesOrSends() {
        var quotes=mock(PaytmPaperReviewAdapter.class);var sender=mock(PaperApprovalDelivery.Sender.class);
        try(var runtime=new PaperPublisherRuntime(target,quotes,sender,"missing-key")) {
            assertFalse(runtime.ready());assertThrows(PaperRuntimeCredential.Locked.class,runtime::open);
            verifyNoInteractions(quotes,sender);
        }
    }
    @Test void publisherAndWriterSecretsAreIndependentAndCloseLocks() {
        var writer=new PaperRuntimeCredential();var runtime=new PaperPublisherRuntime(target,mock(PaytmPaperReviewAdapter.class),mock(PaperApprovalDelivery.Sender.class),"missing");
        byte[] secret="ab".repeat(32).getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        writer.unlock(secret);assertFalse(runtime.ready());runtime.credential().unlock(secret);
        writer.lock();assertTrue(runtime.ready());runtime.close();assertFalse(runtime.ready());
        assertThrows(PaperRuntimeCredential.Locked.class,runtime::open);Arrays.fill(secret,(byte)0);writer.close();
    }
    @ParameterizedTest @ValueSource(strings={"marketbrain-paper-publisher","marketbrain_paper_review_writer","postgres"})
    void connectorRequiresPublisherIdentityAndClearsSecrets(String actual)throws Exception {
        Connection c=mock(Connection.class);Statement s=mock(Statement.class);ResultSet r=mock(ResultSet.class);
        when(c.createStatement()).thenReturn(s);when(s.executeQuery(PaperWriterConnector.IDENTITY_SQL)).thenReturn(r);
        when(r.next()).thenReturn(true,false);when(r.getString(1)).thenReturn(actual);when(r.getString(2)).thenReturn(actual);
        when(r.getString(3)).thenReturn("marketbrain");when(r.getLong(4)).thenReturn(42L);when(r.getBoolean(6)).thenReturn(true);
        char[] secret="ab".repeat(32).toCharArray();Properties[] seen=new Properties[1];
        var connector=new PaperWriterConnector(target,()->secret,true,(url,p)->{seen[0]=p;assertEquals(PaperPaytmReviewPublisher.ROLE,p.getProperty("user"));return c;},PaperPaytmReviewPublisher.ROLE);
        if(actual.equals(PaperPaytmReviewPublisher.ROLE)){assertSame(c,connector.open());verify(c,never()).close();}
        else {assertThrows(SQLException.class,connector::open);verify(c).close();}
        assertArrayEquals(new char[64],secret);assertTrue(seen[0].isEmpty());
    }
    @Test void disabledPublisherCannotReadCredential() {
        var secret=mock(PaperWriterConnector.SecretSource.class);
        assertThrows(SQLException.class,()->PaperWriterConnector.publisher(target,secret,false).open());verifyNoInteractions(secret);
    }
}
