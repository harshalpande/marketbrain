package in.marketbrain.paper;
import org.junit.jupiter.api.Test;
import java.sql.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPublisherCredentialTest {
    final String verifier="SCRAM-SHA-256$4096:"+"A".repeat(22)+"==$"+"B".repeat(43)+"=:"+"C".repeat(43)+"=";
    final PaperPublisherInstallation.Target target=new PaperPublisherInstallation.Target("marketbrain",42,"public");
    @Test void strictInputRejectsExtraFieldsAndVerifierInjection()throws Exception {
        var map=new LinkedHashMap<String,Object>();map.put("url","jdbc:postgresql://host.docker.internal:5432/marketbrain");map.put("user","postgres");map.put("password","secret");map.put("database","marketbrain");map.put("databaseOid",42);map.put("schema","public");map.put("verifier",verifier);
        var mapper=new com.fasterxml.jackson.databind.ObjectMapper();
        assertEquals(verifier,PaperPublisherCredential.read(new ByteArrayInputStream(mapper.writeValueAsBytes(map))).verifier());
        map.put("extra",true);assertThrows(Exception.class,()->PaperPublisherCredential.read(new ByteArrayInputStream(mapper.writeValueAsBytes(map))));
        assertThrows(IllegalArgumentException.class,()->PaperPublisherCredential.validateVerifier(verifier+"'; SELECT 1"));
        assertThrows(Exception.class,()->PaperPublisherCredential.read(new ByteArrayInputStream(new byte[16385])));
    }
    Connection connection(String current,boolean session)throws Exception {
        var c=mock(Connection.class);when(c.getAutoCommit()).thenReturn(true);var s=mock(Statement.class);when(c.createStatement()).thenReturn(s);
        var lock=mock(ResultSet.class);when(lock.next()).thenReturn(true);when(lock.getBoolean(1)).thenReturn(true);when(s.executeQuery(anyString())).thenReturn(lock);
        var p=mock(PreparedStatement.class);when(c.prepareStatement(anyString())).thenReturn(p);var r=mock(ResultSet.class);when(p.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true,false);when(r.getBoolean(2)).thenReturn(!session);when(r.getString(1)).thenReturn(current);return c;
    }
    @Test void stageChangesOnlyPasswordAndRetainsNologin()throws Exception {
        var c=connection(null,false);var report=new HashMap<String,Object>();
        try(var install=mockStatic(PaperPublisherInstall.class,CALLS_REAL_METHODS)) {
            install.when(()->PaperPublisherInstall.verifyInTransaction(c,target,verifier)).thenAnswer(x->null);
            assertEquals("MATCH",PaperPublisherCredential.phase(c,target,verifier,true,true,report));
            verify(c.createStatement()).execute("ALTER ROLE \"marketbrain-paper-publisher\" NOLOGIN PASSWORD '"+verifier+"'");verify(c).commit();assertEquals("COMMITTED",report.get("commitOutcome"));
        }
    }
    @Test void differentPasswordOrExistingSessionNeverMutates()throws Exception {
        for(boolean session:new boolean[]{false,true}) {
            var c=connection(session?null:"other",session);
            try(var install=mockStatic(PaperPublisherInstall.class,CALLS_REAL_METHODS)) {
                install.when(()->PaperPublisherInstall.verifyInTransaction(c,target,verifier)).thenAnswer(x->null);
                assertThrows(SQLException.class,()->PaperPublisherCredential.phase(c,target,verifier,true,true,new HashMap<>()));verify(c,never()).commit();verify(c.createStatement(),never()).execute(anyString());
            }
        }
    }
    @Test void lostCommitIsUnknownAndNotRetried()throws Exception {
        var c=connection(null,false);doThrow(new SQLException("lost")).when(c).commit();var report=new HashMap<String,Object>();
        try(var install=mockStatic(PaperPublisherInstall.class,CALLS_REAL_METHODS)) {
            install.when(()->PaperPublisherInstall.verifyInTransaction(c,target,verifier)).thenAnswer(x->null);
            assertThrows(SQLException.class,()->PaperPublisherCredential.phase(c,target,verifier,true,true,report));assertEquals("UNKNOWN_AFTER_ATTEMPT",report.get("commitOutcome"));verify(c,times(1)).commit();
        }
    }
    @Test void readOnlyExistingMatchHasNoMutation()throws Exception {
        var c=connection(verifier,false);
        try(var install=mockStatic(PaperPublisherInstall.class,CALLS_REAL_METHODS)) {
            install.when(()->PaperPublisherInstall.verifyInTransaction(c,target,verifier)).thenAnswer(x->null);
            assertEquals("MATCH",PaperPublisherCredential.phase(c,target,verifier,false,false,new HashMap<>()));verify(c,never()).commit();verify(c.createStatement(),never()).execute(anyString());verify(c).setReadOnly(true);
        }
    }
    @Test void missingCredentialVerifyOnlyCannotStage()throws Exception {
        var c=mock(Connection.class);var report=new HashMap<String,Object>();
        try(var engine=mockStatic(PaperPublisherCredential.class,CALLS_REAL_METHODS)) {
            engine.when(()->PaperPublisherCredential.phase(c,target,verifier,false,false,report)).thenReturn("MISSING");
            assertThrows(SQLException.class,()->PaperPublisherCredential.execute(c,target,verifier,true,report));engine.verify(()->PaperPublisherCredential.phase(c,target,verifier,true,true,report),never());
        }
    }
    @Test void stagingRequiresRollbackReadbackBeforeCommit()throws Exception {
        var c=mock(Connection.class);var report=new HashMap<String,Object>();
        try(var engine=mockStatic(PaperPublisherCredential.class,CALLS_REAL_METHODS)) {
            engine.when(()->PaperPublisherCredential.phase(c,target,verifier,false,false,report)).thenReturn("MISSING","MATCH");
            engine.when(()->PaperPublisherCredential.phase(c,target,verifier,true,false,report)).thenReturn("MATCH");
            assertThrows(SQLException.class,()->PaperPublisherCredential.execute(c,target,verifier,false,report));engine.verify(()->PaperPublisherCredential.phase(c,target,verifier,true,true,report),never());
        }
    }
}
