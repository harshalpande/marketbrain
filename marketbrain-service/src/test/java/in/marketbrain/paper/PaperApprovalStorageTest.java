package in.marketbrain.paper;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import javax.sql.DataSource;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PaperApprovalStorageTest {
    @TempDir Path directory;
    byte[] key(){byte[] k=new byte[32];Arrays.fill(k,(byte)7);return k;}
    Path keyFile()throws Exception{Path f=directory.resolve("key");Files.writeString(f,Base64.getEncoder().encodeToString(key()));return f;}
    @Test void validFileLoadsWithoutOutput()throws Exception{assertArrayEquals(key(),PaperApprovalStorage.readKey(keyFile().toString()));}
    @ParameterizedTest @ValueSource(strings={"","relative.key","missing"}) void nonexistentOrRelativeRejected(String name){assertThrows(Exception.class,()->PaperApprovalStorage.readKey(name));}
    @ParameterizedTest @ValueSource(strings={"garbage","AAAA","AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","\u0000"}) void invalidOrZeroKeyRejected(String value)throws Exception{Path f=directory.resolve("key");Files.writeString(f,value);assertThrows(Exception.class,()->PaperApprovalStorage.readKey(f.toString()));}
    @Test void oversizedKeyRejectedBeforeDecode()throws Exception{Path f=directory.resolve("key");Files.writeString(f,"a".repeat(129));assertThrows(Exception.class,()->PaperApprovalStorage.readKey(f.toString()));}
    @Test void directoryIsNotAKey(){assertThrows(Exception.class,()->PaperApprovalStorage.readKey(directory.toString()));}
    @Test void defaultDisabledNeverOpensDatabase(){var ds=mock(DataSource.class);var service=new PaperApprovalStorage(ds,false,"","PAPER");service.run(null);assertEquals("DISABLED",service.status().status());verifyNoInteractions(ds);}
    @Test void liveModeNeverBinds(){var ds=mock(DataSource.class);var service=new PaperApprovalStorage(ds,true,"","LIVE");service.run(null);assertEquals("DISABLED",service.status().status());verifyNoInteractions(ds);}
    @Test void missingKeyBlocksWithoutFailingApplication(){var ds=mock(DataSource.class);var service=new PaperApprovalStorage(ds,true,directory.resolve("absent").toString(),"PAPER");assertDoesNotThrow(()->service.run(null));assertEquals("STORAGE_SETUP_BLOCKED",service.status().status());verifyNoInteractions(ds);}
    @Test void databaseErrorIsSanitized()throws Exception{var ds=mock(DataSource.class);when(ds.getConnection()).thenThrow(new SQLException("secret-value"));var service=new PaperApprovalStorage(ds,true,keyFile().toString(),"PAPER");assertDoesNotThrow(()->service.run(null));assertFalse(service.status().toString().contains("secret-value"));assertFalse(service.status().databaseWritesPerformed());}
    @Test void matchingBindingVerifiedAndChangedFileBlocked()throws Exception{
        var ds=mock(DataSource.class);var c=mock(Connection.class);var ps=mock(PreparedStatement.class);var rows=mock(ResultSet.class);
        when(ds.getConnection()).thenReturn(c);when(c.createStatement()).thenReturn(mock(Statement.class));when(c.prepareStatement(anyString())).thenReturn(ps);when(ps.executeQuery()).thenReturn(rows);when(rows.next()).thenReturn(true);
        when(rows.getString(1)).thenReturn(PaperApprovalStorage.fingerprint(key()));when(rows.getString(2)).thenReturn(new PaperApprovalDelivery.Vault(key()).seal("MARKETBRAIN_PAPER_DELIVERY_KEY_V1","MARKETBRAIN_PAPER_DELIVERY_KEY_V1"));
        Path f=keyFile();var service=new PaperApprovalStorage(ds,true,f.toString(),"PAPER");service.run(null);assertEquals("STORAGE_KEY_VERIFIED_ACTIONS_DISABLED",service.status().status());
        byte[] other=new byte[32];Arrays.fill(other,(byte)9);Files.writeString(f,Base64.getEncoder().encodeToString(other));assertEquals("STORAGE_KEY_REVIEW_REQUIRED",service.status().status());verify(c,atLeastOnce()).setReadOnly(true);
    }
    @Test void springDefaultsWireWithoutKeyOrCallback(){new ApplicationContextRunner().withBean(DataSource.class,()->mock(DataSource.class)).withUserConfiguration(PaperApprovalStorage.class,PaperApprovalStorageController.class).run(ctx->{assertNull(ctx.getStartupFailure());assertEquals("DISABLED",ctx.getBean(PaperApprovalStorage.class).status().status());assertFalse(ctx.containsBean("paperApprovalCallback"));});}
    @Test void composeEnvironmentNamesBindToStorageProperties(){new ApplicationContextRunner().withInitializer(ctx->ctx.getEnvironment().getPropertySources().addFirst(new org.springframework.core.env.SystemEnvironmentPropertySource("fixtureEnv",Map.of("MARKETBRAIN_PAPER_APPROVAL_STORAGE_ENABLED","true","MARKETBRAIN_PAPER_APPROVAL_KEY_FILE","/run/secrets/paper-approval.key")))).withBean(DataSource.class,()->mock(DataSource.class)).withUserConfiguration(PaperApprovalStorage.class).run(ctx->{assertNull(ctx.getStartupFailure());assertEquals("STORAGE_SETUP_BLOCKED",ctx.getBean(PaperApprovalStorage.class).status().status());});}
    @Test void unauthorizedReadNeverCallsStorage()throws Exception{var service=mock(PaperApprovalStorage.class);var mvc=MockMvcBuilders.standaloneSetup(new PaperApprovalStorageController(service,"a".repeat(64),"PAPER")).build();mvc.perform(get("/api/v1/paper/approval/storage")).andExpect(status().isUnauthorized());verifyNoInteractions(service);}
    @Test void authorizedStatusIsNotWriteAuthority()throws Exception{var service=mock(PaperApprovalStorage.class);when(service.status()).thenReturn(new PaperApprovalStorage.Status("PAPER_APPROVAL_STORAGE_V1","DISABLED",false,false,false,false));var mvc=MockMvcBuilders.standaloneSetup(new PaperApprovalStorageController(service,"a".repeat(64),"PAPER")).build();mvc.perform(get("/api/v1/paper/approval/storage").header("X-MarketBrain-Paper-Read-Token","a".repeat(64))).andExpect(status().isOk()).andExpect(header().string("Cache-Control","no-store")).andExpect(jsonPath("$.actionExecutionEnabled").value(false));mvc.perform(post("/api/v1/paper/approval/storage")).andExpect(status().isMethodNotAllowed());}
    @Test void disabledReadConfigurationFailsClosed()throws Exception{var service=mock(PaperApprovalStorage.class);var mvc=MockMvcBuilders.standaloneSetup(new PaperApprovalStorageController(service,"","PAPER")).build();mvc.perform(get("/api/v1/paper/approval/storage")).andExpect(status().isServiceUnavailable());verifyNoInteractions(service);}
    @Test void promotedSqlMatchesAcceptedCandidateExecutableStatements()throws Exception{
        String combined=PaperLedgerVerification.resource("/db/migration/V28__attach_paper_approval_storage.sql");
        for(String name:List.of("approval-v1.sql","delivery-v1.sql")){String candidate=PaperLedgerVerification.resource("/paper/"+name);String executable=candidate.replaceAll("(?m)^--.*$","").replaceAll("\\s+"," ").trim();assertTrue(combined.replaceAll("(?m)^--.*$","").replaceAll("\\s+"," ").contains(executable));}
        assertFalse(combined.contains("UPDATE paper_portfolio"));assertFalse(combined.contains("INSERT INTO paper_portfolio"));
    }
}
