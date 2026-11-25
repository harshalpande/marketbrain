package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.sql.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Transaction/target contracts only. PostgreSQL execution is verified by the disposable suite. */
class PaperPublisherInstallationTest {
    final PaperPublisherInstallation.Target target=new PaperPublisherInstallation.Target("marketbrain",42,"public");
    Connection connection(String failure)throws Exception {
        var c=mock(Connection.class);var s=mock(Statement.class);when(c.getAutoCommit()).thenReturn(true);when(c.createStatement()).thenReturn(s);
        var identity=mock(ResultSet.class);when(identity.next()).thenReturn(true);when(identity.getString(1)).thenReturn(failure.equals("database")?"postgres":"marketbrain");
        when(identity.getLong(2)).thenReturn(failure.equals("oid")?43L:42L);when(identity.getBoolean(3)).thenReturn(!failure.equals("admin"));
        when(s.executeQuery(anyString())).thenReturn(identity);
        when(c.prepareStatement(anyString())).thenAnswer(call->{String sql=call.getArgument(0);var p=mock(PreparedStatement.class);var r=mock(ResultSet.class);
            when(p.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true);
            when(r.getLong(1)).thenReturn((failure.equals("role")&&sql.contains("pg_roles"))||(failure.equals("function")&&sql.contains("pg_proc"))||(failure.equals("default-grant")&&sql.contains("pg_proc")&&sql.contains("aclexplode"))?1L:0L);
            when(r.getBoolean(1)).thenReturn(!failure.equals("schema"));return p;});
        return c;
    }
    @ParameterizedTest @ValueSource(strings={"database","oid","admin","role","function","schema"})
    void targetAndCollisionFailuresRollBackWithoutCreatingRoles(String failure)throws Exception {
        var c=connection(failure);assertThrows(SQLException.class,()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED));
        verify(c).rollback();verify(c,never()).commit();verify(c.createStatement(),never()).execute(startsWith("CREATE ROLE"));verify(c).setAutoCommit(true);
    }
    @Test void rehearsalExecutesInstallationButNeverCommits()throws Exception {
        var c=connection("");var r=PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK);
        assertFalse(r.committed());assertFalse(r.loginEnabled());verify(c).rollback();verify(c,never()).commit();
        verify(c.createStatement(),times(2)).execute(matches("CREATE ROLE .* NOLOGIN .*"));
    }
    @Test void explicitInstallCommitsDisabledRolesOnly()throws Exception {
        var c=connection("");var r=PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED);
        assertTrue(r.committed());assertFalse(r.loginEnabled());assertFalse(r.applicationActivated());verify(c).commit();verify(c,never()).rollback();
        verify(c.createStatement(),never()).execute(contains(" PASSWORD "));verify(c.createStatement(),never()).execute(startsWith("REVOKE ALL ON ALL"));
    }
    @Test void lateFailureRollsBackRoleAndFunctionChanges()throws Exception {
        var c=connection("");when(c.createStatement().execute(startsWith("GRANT INSERT"))).thenThrow(new SQLException("synthetic"));
        assertThrows(SQLException.class,()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED));
        verify(c.createStatement(),times(2)).execute(startsWith("CREATE ROLE"));verify(c).rollback();verify(c,never()).commit();
    }
    @Test void refusesCallerOwnedTransaction()throws Exception {
        var c=connection("");when(c.getAutoCommit()).thenReturn(false);
        assertThrows(SQLException.class,()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED));
        verify(c,never()).setAutoCommit(anyBoolean());verify(c,never()).rollback();
    }
    @Test void unexpectedDefaultExecuteGrantRollsBackInstallation()throws Exception {
        var c=connection("default-grant");
        assertEquals("PUBLISHER_INSTALL_UNEXPECTED_EXECUTE_GRANT",assertThrows(SQLException.class,()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED)).getMessage());
        verify(c.createStatement(),times(2)).execute(startsWith("CREATE ROLE"));verify(c).rollback();verify(c,never()).commit();
    }
    @ParameterizedTest @ValueSource(strings={"public; DROP ROLE x","public\"","a.b",""})
    void identifiersRejectSqlInjection(String schema) {
        assertThrows(IllegalArgumentException.class,()->new PaperPublisherInstallation.Target("marketbrain",42,schema));
    }
}
