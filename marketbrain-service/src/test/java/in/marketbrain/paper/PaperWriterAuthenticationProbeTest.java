package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import java.io.ByteArrayInputStream;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.sql.*;
import java.util.Properties;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperWriterAuthenticationProbeTest {
    @Test void deployedBootClassLayoutLoadsConnectorWithoutSpringOrJackson() throws Exception {
        Path jar=Files.createTempFile("writer-auth-layout-",".jar");
        try {
            try(JarOutputStream out=new JarOutputStream(Files.newOutputStream(jar))) {
                for(String name:new String[]{"PaperWriterConnector","PaperWriterConnector$Target","PaperWriterConnector$Transport","PaperWriterConnector$SecretSource","PaperWriterConnector$Dialer","PaperLedgerStore$Connections"}) {
                    String path="in/marketbrain/paper/"+name+".class";
                    out.putNextEntry(new JarEntry("BOOT-INF/classes/"+path));
                    try(var input=getClass().getClassLoader().getResourceAsStream(path)){assertNotNull(input);input.transferTo(out);}out.closeEntry();
                }
            }
            try(URLClassLoader loader=new URLClassLoader(new java.net.URL[]{new java.net.URI("jar:"+jar.toUri()+"!/BOOT-INF/classes/").toURL()},ClassLoader.getPlatformClassLoader())) {
                Object value=PaperWriterAuthenticationProbe.configuredConnector(loader,"marketbrain",5432,16389,"a".repeat(64).toCharArray());
                assertEquals(PaperWriterAuthenticationProbe.PREFIX,value.getClass().getName());assertSame(loader,value.getClass().getClassLoader());
                assertNotNull(value.getClass().getMethod("open"));
            }
        } finally { Files.deleteIfExists(jar); }
    }
    @Test void stdinIsExactLowerHexWithoutNewline() throws Exception {
        assertArrayEquals("a".repeat(64).toCharArray(),PaperWriterAuthenticationProbe.password(new ByteArrayInputStream("a".repeat(64).getBytes())));
        for(String bad:new String[]{"a".repeat(63),"a".repeat(65),"A".repeat(64),"a".repeat(63)+"\n","z".repeat(64)})
            assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.password(new ByteArrayInputStream(bad.getBytes())));
    }
    @Test void propertiesUseOnlyWriterAndBoundedPrivateRoute() {
        Properties p=PaperWriterAuthenticationProbe.properties("a".repeat(64).toCharArray(),"b".repeat(32));
        assertEquals("marketbrain_paper_review_writer",p.getProperty("user"));assertEquals("disable",p.getProperty("sslmode"));
        assertEquals("5",p.getProperty("socketTimeout"));assertTrue(p.getProperty("options").contains("default_transaction_read_only=on"));
    }
    @Test void onlyExpectedAuthenticationStateCountsAsDenied() throws Exception {
        Driver d=mock(Driver.class);Properties p=new Properties();p.setProperty("password","synthetic");
        when(d.connect(anyString(),any())).thenThrow(new SQLException("secret must not escape","28P01"));
        PaperWriterAuthenticationProbe.denied(d,"url",p,"28P01");assertTrue(p.isEmpty());
        var failure=assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.denied(d,"url",new Properties(),"28000"));
        assertEquals("AUTH_DENIAL_STATE_MISMATCH",failure.getMessage());
    }
    @Test void successfulConnectionIsFailureAndClosed() throws Exception {
        Driver d=mock(Driver.class);Connection c=mock(Connection.class);when(d.connect(anyString(),any())).thenReturn(c);
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.denied(d,"url",new Properties(),"28000"));verify(c).close();
    }
    @Test void nullDriverResultIsNotRejection() throws Exception {
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.denied(mock(Driver.class),"url",new Properties(),"28000"));
    }
    @Test void targetDoesNotAcceptUrlOptionsOrOtherHost() {
        String url="jdbc:postgresql://host.docker.internal:5432/marketbrain";
        assertEquals(url,PaperWriterAuthenticationProbe.target(url,"marketbrain","5432","16389","a".repeat(32),"123.000000"));
        for(String bad:new String[]{url+"?user=postgres",url.replace("host.docker.internal","localhost"),""})
            assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.target(bad,"marketbrain","5432","16389","a".repeat(32),"123.000000"));
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.target(url,"postgres","5432","16389","a".repeat(32),"123.000000"));
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.target(url,"marketbrain","5432","16389","';select","123.000000"));
    }
    private Connection route(boolean bad) throws Exception {
        Connection c=mock(Connection.class);Statement s=mock(Statement.class);ResultSet r=mock(ResultSet.class);
        when(c.createStatement()).thenReturn(s);when(s.executeQuery(startsWith("SELECT host"))).thenReturn(r);when(r.next()).thenReturn(true,false);
        when(r.getString(1)).thenReturn(bad?"10.0.0.1":"127.0.0.1");when(r.getString(2)).thenReturn("127.0.0.1");
        when(r.getInt(3)).thenReturn(5432);when(r.getString(4)).thenReturn("123.000000");when(r.getString(5)).thenReturn("on");
        when(s.executeQuery(startsWith("SELECT *"))).thenThrow(new SQLException("denied","42501"));return c;
    }
    @Test void correctRouteAndFourPermissionDenialsCloseAndRollback() throws Exception {
        Connection c=route(false);PaperWriterAuthenticationProbe.inspect(c,"123.000000");
        verify(c).setReadOnly(true);verify(c).setAutoCommit(false);verify(c,times(4)).setSavepoint();verify(c).rollback();verify(c).close();
        verify(c.createStatement(),never()).executeUpdate(anyString());
    }
    @Test void routeMismatchClosesAndRollsBack() throws Exception {
        Connection c=route(true);assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.inspect(c,"123.000000"));verify(c).close();verify(c).rollback();
    }
    @Test void wrongPermissionFailureIsNotAccepted() throws Exception {
        Connection c=route(false);when(c.createStatement().executeQuery(startsWith("SELECT *"))).thenThrow(new SQLException("no table","42P01"));
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.inspect(c,"123.000000"));verify(c).close();
    }
    @Test void leakedSelectPrivilegeIsNotAccepted() throws Exception {
        Connection c=route(false);when(c.createStatement().executeQuery(startsWith("SELECT *"))).thenReturn(mock(ResultSet.class));
        assertThrows(IllegalArgumentException.class,()->PaperWriterAuthenticationProbe.inspect(c,"123.000000"));verify(c).close();
    }
}
