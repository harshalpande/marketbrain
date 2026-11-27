package in.marketbrain.paper;

import java.sql.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPublisherInstallTest {
    final PaperPublisherInstallation.Target target=new PaperPublisherInstallation.Target("marketbrain",42,"public");
    ResultSet row()throws Exception {var r=mock(ResultSet.class);when(r.next()).thenReturn(true,false);return r;}
    Connection connection(String failure)throws Exception {
        var c=mock(Connection.class);when(c.getAutoCommit()).thenReturn(true);var s=mock(Statement.class);when(c.createStatement()).thenReturn(s);
        when(s.executeQuery(anyString())).thenAnswer(call->{String sql=call.getArgument(0);var r=row();
            if(sql.contains("current_database")){when(r.getString(1)).thenReturn("marketbrain");when(r.getLong(2)).thenReturn(failure.equals("oid")?43L:42L);when(r.getBoolean(3)).thenReturn(!failure.equals("admin"));}
            else if(sql.contains("pg_authid")){when(r.getInt(1)).thenReturn(2);when(r.getBoolean(2)).thenReturn(!failure.equals("login"));}
            else{when(r.getInt(1)).thenReturn(failure.equals("membership")?1:0);}return r;});
        var bodies=PaperPublisherInstall.expectedBodies("public");var index=new AtomicInteger();
        when(c.prepareStatement(anyString())).thenAnswer(call->{String sql=call.getArgument(0);var p=mock(PreparedStatement.class);var r=row();when(p.executeQuery()).thenReturn(r);
            if(sql.contains("p.prosrc")) {
                String name=List.of("paper_publish_enqueue","paper_publish_lock","paper_publish_transition").get(index.getAndIncrement());
                when(r.getString(1)).thenReturn(name);when(r.getString(2)).thenReturn(failure.equals("body")?"other":bodies.get(name));when(r.getBoolean(3)).thenReturn(!failure.equals("definer"));
                when(r.getString(4)).thenReturn(PaperPublisherInstallation.HELPER);var a=mock(java.sql.Array.class);when(a.getArray()).thenReturn(new String[]{failure.equals("path")?"search_path=public":"search_path=pg_catalog, public, pg_temp"});when(r.getArray(5)).thenReturn(a);
                when(r.getString(6)).thenReturn("plpgsql");when(r.getInt(7)).thenReturn(name.endsWith("enqueue")?25:16);when(r.getBoolean(8)).thenReturn(!failure.equals("execute-grant"));when(r.getBoolean(9)).thenReturn(true);
            }else if(sql.contains("pg_class")){when(r.getInt(1)).thenReturn(20);when(r.getBoolean(2)).thenReturn(failure.equals("table-write"));}
            else if(sql.contains("has_schema_privilege")){when(r.getBoolean(1)).thenReturn(!failure.equals("schema"));}
            else{when(r.getInt(1)).thenReturn(failure.equals("function-count")?4:3);}return p;});
        return c;
    }
    @Test void readbackRequiresExactBodiesAndNeverCommits()throws Exception {
        var c=connection("");PaperPublisherInstall.verify(c,target);verify(c).rollback();verify(c,never()).commit();verify(c.createStatement(),never()).execute(anyString());
        assertEquals(3,PaperPublisherInstall.expectedBodies("public").size());
    }
    @ParameterizedTest @ValueSource(strings={"oid","admin","login","membership","body","definer","path","execute-grant","table-write","schema","function-count"})
    void alteredStateRejected(String failure)throws Exception {var c=connection(failure);assertThrows(SQLException.class,()->PaperPublisherInstall.verify(c,target));verify(c).rollback();verify(c,never()).commit();}
    @Test void callerTransactionNeverCommittedByVerification()throws Exception {
        var c=connection("");when(c.getAutoCommit()).thenReturn(false);assertThrows(SQLException.class,()->PaperPublisherInstall.verify(c,target));verify(c,never()).setAutoCommit(anyBoolean());verify(c,never()).commit();
    }
    @Test void verifyOnlyCannotInvokeInstaller()throws Exception {
        try(var rehearsal=mockStatic(PaperPublisherRehearsal.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            install.when(()->PaperPublisherInstallation.quoted("public")).thenReturn("\"public\"");
            var r=new HashMap<String,Object>();PaperPublisherInstall.execute(connection(""),target,true,r);
            assertEquals("PUBLISHER_DISABLED_STATE_VERIFIED",r.get("status"));rehearsal.verifyNoInteractions();
            install.verify(()->PaperPublisherInstallation.run(any(),any(),any()),never());
        }
    }
    @Test void commitAcknowledgedButReadbackFailureRemainsCommitted()throws Exception {
        var c=connection("body");var report=new HashMap<String,Object>();
        try(var rehearsal=mockStatic(PaperPublisherRehearsal.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            install.when(()->PaperPublisherInstallation.quoted("public")).thenReturn("\"public\"");
            install.when(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED)).thenReturn(new PaperPublisherInstallation.Receipt("PUBLISHER_INSTALLED_LOGIN_DISABLED",true,false,false));
            assertThrows(SQLException.class,()->PaperPublisherInstall.execute(c,target,false,report));assertEquals("COMMITTED",report.get("commitOutcome"));
            rehearsal.verify(()->PaperPublisherRehearsal.rehearse(c,target));
        }
    }
    @Test void lostCommitAcknowledgementRemainsUnknownAndIsNotRetried()throws Exception {
        var c=connection("");var report=new HashMap<String,Object>();
        try(var rehearsal=mockStatic(PaperPublisherRehearsal.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            install.when(()->PaperPublisherInstallation.quoted("public")).thenReturn("\"public\"");
            install.when(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED)).thenThrow(new SQLException("lost"));
            assertThrows(SQLException.class,()->PaperPublisherInstall.execute(c,target,false,report));assertEquals("UNKNOWN_AFTER_ATTEMPT",report.get("commitOutcome"));
            install.verify(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED),times(1));
        }
    }
}
