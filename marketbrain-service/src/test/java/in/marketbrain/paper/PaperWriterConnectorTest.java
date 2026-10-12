package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Offline contract checks, NOT proof of TLS negotiation, server identity or installed permissions. */
class PaperWriterConnectorTest {
    @TempDir Path directory;
    private PaperWriterConnector.Target target() throws Exception {
        Path cert = directory.resolve("synthetic-ca.pem");
        if (!Files.exists(cert)) Files.writeString(cert, "offline fixture, not a certificate");
        return new PaperWriterConnector.Target("host.docker.internal", 5432, "marketbrain", 16389, PaperWriterConnector.Transport.VERIFIED_TLS, cert);
    }
    @Test void disabledDoesNotReadSecretOrDial() throws Exception {
        var secret = mock(PaperWriterConnector.SecretSource.class); var dial = mock(PaperWriterConnector.Dialer.class);
        assertThrows(SQLException.class, () -> new PaperWriterConnector(target(), secret, false, dial).open());
        verifyNoInteractions(secret, dial);
    }
    @ParameterizedTest @ValueSource(strings={"host/?sslmode=disable", "host,user", "host\n", "-bad", "a..b", ""})
    void rejectsUrlInjection(String host) {
        assertThrows(IllegalArgumentException.class, () -> new PaperWriterConnector.Target(host,5432,"marketbrain",1,PaperWriterConnector.Transport.VERIFIED_TLS,directory.resolve("ca")));
    }
    @Test void missingCertificateStopsBeforeSecret() throws Exception {
        var secret=mock(PaperWriterConnector.SecretSource.class); var dial=mock(PaperWriterConnector.Dialer.class);
        var t=new PaperWriterConnector.Target("localhost",5432,"marketbrain",1,PaperWriterConnector.Transport.VERIFIED_TLS,directory.resolve("missing"));
        assertThrows(SQLException.class,()->new PaperWriterConnector(t,secret,true,dial).open());
        verifyNoInteractions(secret,dial);
    }
    @Test void driverFailureIsSanitizedAndBuffersCleared() throws Exception {
        char[] secret="SYNTHETIC_ONLY_012345678901234567890".toCharArray();
        Properties[] seen=new Properties[1];
        var connector=new PaperWriterConnector(target(),()->secret,true,(url,p)->{
            seen[0]=p; assertEquals("verify-full",p.getProperty("sslmode"));
            assertEquals(PaperWriterConnector.ROLE,p.getProperty("user"));
            assertEquals("10",p.getProperty("connectTimeout")); assertEquals("15",p.getProperty("socketTimeout"));
            assertEquals("15",p.getProperty("loginTimeout"));
            assertEquals(directory.resolve("synthetic-ca.pem").toString(),p.getProperty("sslrootcert"));
            assertEquals("jdbc:postgresql://host.docker.internal:5432/marketbrain",url);
            throw new SQLException(new String(secret));
        });
        SQLException failure=assertThrows(SQLException.class,connector::open);
        assertNull(failure.getCause()); assertFalse(failure.toString().contains("SYNTHETIC"));
        assertArrayEquals(new char[secret.length],secret); assertTrue(seen[0].isEmpty());
    }
    @ParameterizedTest @ValueSource(ints={0,1,2,3,4,5,6,7})
    void identityChecksFailClosed(int bad) throws Exception {
        Connection c=mock(Connection.class); Statement s=mock(Statement.class); ResultSet r=mock(ResultSet.class);
        when(c.createStatement()).thenReturn(s); when(s.executeQuery(PaperWriterConnector.IDENTITY_SQL)).thenReturn(r);
        when(r.next()).thenReturn(bad!=0,bad==7);
        when(r.getString(1)).thenReturn(bad==1?"owner":PaperWriterConnector.ROLE);
        when(r.getString(2)).thenReturn(bad==2?"owner":PaperWriterConnector.ROLE);
        when(r.getString(3)).thenReturn(bad==3?"postgres":"marketbrain");
        when(r.getLong(4)).thenReturn(bad==4?1L:16389L);
        when(r.getBoolean(5)).thenReturn(bad!=5); when(r.getBoolean(6)).thenReturn(bad!=6);
        var connector=new PaperWriterConnector(target(),()->"SYNTHETIC_ONLY_012345678901234567890".toCharArray(),true,(u,p)->c);
        assertThrows(SQLException.class,connector::open); verify(c).close(); verify(c,never()).setReadOnly(false);
        verify(s).setQueryTimeout(5); verify(r).close(); verify(s).close();
    }
    @Test void verifiedConnectionReturnedWithoutCommandsOrActivationWiring() throws Exception {
        Connection c=mock(Connection.class); Statement s=mock(Statement.class); ResultSet r=mock(ResultSet.class);
        when(c.createStatement()).thenReturn(s); when(s.executeQuery(PaperWriterConnector.IDENTITY_SQL)).thenReturn(r);
        when(r.next()).thenReturn(true,false); when(r.getString(1)).thenReturn(PaperWriterConnector.ROLE);
        when(r.getString(2)).thenReturn(PaperWriterConnector.ROLE); when(r.getString(3)).thenReturn("marketbrain");
        when(r.getLong(4)).thenReturn(16389L); when(r.getBoolean(5)).thenReturn(true); when(r.getBoolean(6)).thenReturn(true);
        assertSame(c,new PaperWriterConnector(target(),()->"SYNTHETIC_ONLY_012345678901234567890".toCharArray(),true,(u,p)->c).open());
        verify(c).setReadOnly(true); verify(c).setReadOnly(false); verify(c,never()).close(); verify(c,never()).commit();
        verify(s).executeQuery(PaperWriterConnector.IDENTITY_SQL); verify(s,never()).executeUpdate(anyString());
    }
    @Test void invalidPasswordRejectedAndCleared() throws Exception {
        char[] secret="short".toCharArray(); var dial=mock(PaperWriterConnector.Dialer.class);
        assertThrows(SQLException.class,()->new PaperWriterConnector(target(),()->secret,true,dial).open());
        assertArrayEquals(new char[5],secret); verifyNoInteractions(dial);
    }
    @ParameterizedTest @ValueSource(strings={"192.168.1.2", "db.example.com", "localhost.example.com", "127.0.0.2"})
    void privatePolicyDoesNotAcceptArbitraryHosts(String host) {
        assertThrows(IllegalArgumentException.class, () -> new PaperWriterConnector.Target(host,5432,"marketbrain",1,PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null));
    }
    @ParameterizedTest @ValueSource(strings={"localhost", "127.0.0.1", "host.docker.internal"})
    void explicitPrivatePolicyNeedsNoCertificateButStillChecksIdentity(String host) throws Exception {
        Connection c=mock(Connection.class); Statement s=mock(Statement.class); ResultSet r=mock(ResultSet.class);
        when(c.createStatement()).thenReturn(s); when(s.executeQuery(PaperWriterConnector.IDENTITY_SQL)).thenReturn(r);
        when(r.next()).thenReturn(true,false); when(r.getString(1)).thenReturn(PaperWriterConnector.ROLE);
        when(r.getString(2)).thenReturn(PaperWriterConnector.ROLE); when(r.getString(3)).thenReturn("marketbrain");
        when(r.getLong(4)).thenReturn(16389L); when(r.getBoolean(5)).thenReturn(false); when(r.getBoolean(6)).thenReturn(true);
        var t=new PaperWriterConnector.Target(host,5432,"marketbrain",16389,PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null);
        assertSame(c,new PaperWriterConnector(t,()->"SYNTHETIC_ONLY_012345678901234567890".toCharArray(),true,(u,p)->{
            assertEquals("disable",p.getProperty("sslmode")); assertEquals("disable",p.getProperty("gssEncMode"));
            assertNull(p.getProperty("sslrootcert")); return c;
        }).open());
        verify(s).executeQuery(PaperWriterConnector.IDENTITY_SQL); verify(c,never()).commit();
    }
}
