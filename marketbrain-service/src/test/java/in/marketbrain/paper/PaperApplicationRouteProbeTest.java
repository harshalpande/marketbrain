package in.marketbrain.paper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.sql.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class PaperApplicationRouteProbeTest {
    @Test void queryUsesHostTextWithoutInetMask(){
        assertTrue(PaperApplicationRouteProbe.SQL.contains("host(inet_client_addr())"));
        assertTrue(PaperApplicationRouteProbe.SQL.contains("host(inet_server_addr())"));
        assertFalse(PaperApplicationRouteProbe.SQL.contains("inet_client_addr()::text"));
        assertFalse(PaperApplicationRouteProbe.SQL.contains("inet_server_addr()::text"));
    }
    @ParameterizedTest @ValueSource(strings={"jdbc:postgresql://evil:5432/marketbrain","jdbc:postgresql://host.docker.internal:5432/marketbrain?user=owner","jdbc:postgresql://localhost:5432/marketbrain",""})
    void refusesDifferentRouteOrOptions(String url){assertThrows(IllegalArgumentException.class,()->PaperApplicationRouteProbe.approvedUrl(url,"marketbrain","5432"));}
    @Test void fixedPolicy(){assertEquals("jdbc:postgresql://host.docker.internal:5432/marketbrain",PaperApplicationRouteProbe.approvedUrl("jdbc:postgresql://host.docker.internal:5432/marketbrain","marketbrain","5432"));
        var p=PaperApplicationRouteProbe.properties("app","SYNTHETIC","a".repeat(32));assertEquals("disable",p.getProperty("sslmode"));assertTrue(p.getProperty("options").contains("default_transaction_read_only=on"));assertEquals("10",p.getProperty("socketTimeout"));}
    @ParameterizedTest @ValueSource(strings={"0","65536","-1","5432;"})
    void badPort(String port){assertThrows(IllegalArgumentException.class,()->PaperApplicationRouteProbe.approvedUrl("", "marketbrain",port));}
    @Test void readsMetadataAndRollsBack()throws Exception{Driver d=mock(Driver.class);Connection c=mock(Connection.class);Statement s=mock(Statement.class);ResultSet r=mock(ResultSet.class);
        var p=PaperApplicationRouteProbe.properties("app","SYNTHETIC","a".repeat(32));when(d.connect("url",p)).thenReturn(c);when(c.createStatement()).thenReturn(s);when(s.executeQuery(PaperApplicationRouteProbe.SQL)).thenReturn(r);when(r.next()).thenReturn(true,false);when(r.getString(1)).thenReturn("{}");
        assertEquals("{}",PaperApplicationRouteProbe.inspect(d,"url",p));assertTrue(p.isEmpty());verify(c).rollback();verify(c,never()).commit();verify(c).close();verify(c).setReadOnly(true);verify(s).setQueryTimeout(5);}
    @Test void failureStillClosesAndClears()throws Exception{Driver d=mock(Driver.class);Connection c=mock(Connection.class);var p=PaperApplicationRouteProbe.properties("app","SYNTHETIC","a".repeat(32));when(d.connect("url",p)).thenReturn(c);when(c.createStatement()).thenThrow(new SQLException("test"));assertThrows(SQLException.class,()->PaperApplicationRouteProbe.inspect(d,"url",p));assertTrue(p.isEmpty());verify(c).close();verify(c,never()).commit();}
}
