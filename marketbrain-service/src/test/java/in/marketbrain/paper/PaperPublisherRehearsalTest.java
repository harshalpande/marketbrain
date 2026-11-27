package in.marketbrain.paper;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayInputStream;
import java.sql.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPublisherRehearsalTest {
    Map<String,Object> input(){return new LinkedHashMap<>(Map.of("url","jdbc:postgresql://host.docker.internal:5432/marketbrain","user","postgres","password","fixture-only","database","marketbrain","databaseOid",42,"schema","public"));}
    PaperPublisherRehearsal.Request parse(Map<String,Object> input)throws Exception{return PaperPublisherRehearsal.read(new ByteArrayInputStream(new ObjectMapper().writeValueAsBytes(input)));}
    @Test void validRequestHasBoundedConnectionWithoutReadonlyOverride()throws Exception {
        var r=parse(input());var p=PaperPublisherRehearsal.properties(r);
        assertEquals("5",p.getProperty("connectTimeout"));assertEquals("30",p.getProperty("socketTimeout"));assertFalse(p.containsKey("readOnlyMode"));
        assertEquals(42,r.target().databaseOid());
    }
    @ParameterizedTest @ValueSource(strings={"url","user","password","database","databaseOid","schema"})
    void missingFieldsRejected(String key){var v=input();v.remove(key);assertThrows(Exception.class,()->parse(v));}
    @ParameterizedTest @ValueSource(strings={"mode","execute","unknown"})
    void noCommitOrOtherExtraFields(String key){var v=input();v.put(key,"INSTALL_DISABLED");assertThrows(Exception.class,()->parse(v));}
    @Test void rejectsCoercionAndUrlEscapeHatches() {
        var v=input();v.put("databaseOid","42");assertThrows(Exception.class,()->parse(v));
        var bad=input();bad.put("url","jdbc:postgresql://host/db?password=secret");assertThrows(Exception.class,()->parse(bad));
    }
    @Test void inputBound(){assertThrows(Exception.class,()->PaperPublisherRehearsal.read(new ByteArrayInputStream(new byte[16385])));}
    Map<String,Object> catalog(){return new LinkedHashMap<>(Map.of("target",Map.of("database","marketbrain","databaseOid",42),"session",Map.of("superuser",true),"installationBlockers",List.of(),"catalogListBoundReached",false));}
    @Test void alwaysUsesRollbackModeAndRequiresReadback()throws Exception {
        var c=mock(Connection.class);var target=new PaperPublisherInstallation.Target("marketbrain",42,"public");var before=catalog();
        try(var pre=mockStatic(PaperWriterPreflight.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            pre.when(()->PaperWriterPreflight.inspect(c,"public",true)).thenReturn(before,new LinkedHashMap<>(before));
            install.when(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK)).thenReturn(new PaperPublisherInstallation.Receipt("PUBLISHER_INSTALL_REHEARSED_ROLLED_BACK",false,false,false));
            assertEquals(true,PaperPublisherRehearsal.rehearse(c,target).get("rollbackVerified"));
            install.verify(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK));install.verifyNoMoreInteractions();
            pre.verify(()->PaperWriterPreflight.inspect(c,"public",true),times(2));verify(c,never()).commit();
        }
    }
    @Test void catalogDriftRefusesSuccess()throws Exception {
        var c=mock(Connection.class);var target=new PaperPublisherInstallation.Target("marketbrain",42,"public");var after=catalog();after.put("changed",true);
        try(var pre=mockStatic(PaperWriterPreflight.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            pre.when(()->PaperWriterPreflight.inspect(c,"public",true)).thenReturn(catalog(),after);
            install.when(()->PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK)).thenReturn(new PaperPublisherInstallation.Receipt("PUBLISHER_INSTALL_REHEARSED_ROLLED_BACK",false,false,false));
            assertThrows(SQLException.class,()->PaperPublisherRehearsal.rehearse(c,target));
        }
    }
    @Test void blockedCatalogNeverInvokesInstaller()throws Exception {
        var c=mock(Connection.class);var blocked=catalog();blocked.put("installationBlockers",List.of("EXISTING_ROLE"));
        try(var pre=mockStatic(PaperWriterPreflight.class);var install=mockStatic(PaperPublisherInstallation.class)) {
            pre.when(()->PaperWriterPreflight.inspect(c,"public",true)).thenReturn(blocked);
            assertThrows(SQLException.class,()->PaperPublisherRehearsal.rehearse(c,new PaperPublisherInstallation.Target("marketbrain",42,"public")));install.verifyNoInteractions();
        }
    }
}
