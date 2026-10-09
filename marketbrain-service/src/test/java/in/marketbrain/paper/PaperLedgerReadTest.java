package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import java.nio.charset.StandardCharsets;
import java.sql.ResultSet;
import java.time.Instant;
import java.util.List;
import java.math.BigDecimal;
import static in.marketbrain.paper.PaperAccountReadService.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class PaperLedgerReadTest {
    Overview base() { return assess(List.of(new Account("1", "Default Paper Portfolio", "PAPER", "100000.00", "100000.00")), false, false, Instant.EPOCH); }
    LedgerRow opening() { return new LedgerRow(10000000,10000000,0,0,null,null,"0".repeat(64)); }
    @Test void pristineLedgerIsExactReadOnlyNotBuyingPermission() {
        var v=attachView(base(),opening(),false);
        assertEquals("PAPER_ACCOUNT_OVERVIEW_V2",v.version());
        assertEquals("LEDGER_ATTACHED_READ_ONLY",v.migrationAssessment());
        assertEquals(new Ledger("ATTACHED_READ_ONLY","100000.00","0.00","100000.00","0"),v.ledger());
        assertEquals(2,v.blockers().size());assertFalse(v.actionExecutionEnabled());assertFalse(v.databaseWritesPerformed());
    }
    @Test void missingAttachmentHasNoInventedZeros() {assertEquals(new Ledger("NOT_ATTACHED",null,null,null,null),base().ledger());}
    @Test void activityWithholdsAmounts() {blocked(attachView(base(),opening(),true));}
    @ParameterizedTest @ValueSource(strings={"opening","cash","reserved","revision","time","policy","tail"})
    void corruptedOrAdvancedProjectionWithholdsAmounts(String field) {
        var r=opening();var changed=new LedgerRow(field.equals("opening")?1:r.opening(),field.equals("cash")?1:r.cash(),
            field.equals("reserved")?1:0,field.equals("revision")?1:0,field.equals("time")?Instant.EPOCH:null,
            field.equals("policy")?"{}":null,field.equals("tail")?"x":r.tail());
        blocked(attachView(base(),changed,false));
    }
    @Test void legacyHistoryBlocksEvenMatchingLedger() {
        var v=assess(List.of(base().account()),true,false,Instant.EPOCH);blocked(attachView(v,opening(),false));
    }
    @Test void wrongAccountIdentityCannotClaimAttachment() {
        var v=assess(List.of(new Account("2","other","PAPER","100000.00","100000.00")),false,false,Instant.EPOCH);
        blocked(attachView(v,opening(),false));
    }
    void blocked(Overview v) {assertEquals("REVIEW_REQUIRED",v.ledger().status());assertNull(v.ledger().cash());assertNull(v.ledger().revision());assertTrue(v.blockers().contains("LEDGER_RECONCILIATION_REQUIRED"));}
    @Test void promotedSqlEqualsVerifiedCandidateExceptComment() throws Exception {
        String candidate=resource("/paper/ledger-v1.sql");String promoted=resource("/db/migration/V27__attach_paper_application_ledger.sql");
        assertEquals(executable(candidate),executable(promoted));
        assertFalse(PaperLedgerStore.class.isAnnotationPresent(org.springframework.stereotype.Service.class));
    }
    String resource(String path)throws Exception {try(var in=getClass().getResourceAsStream(path)){assertNotNull(in);return new String(in.readAllBytes(),StandardCharsets.UTF_8);}}
    String executable(String value){return value.lines().filter(l->!l.startsWith("--")).map(String::stripTrailing).filter(l->!l.isBlank()).reduce("",(a,b)->a+b+"\n");}
    @Test @SuppressWarnings("unchecked") void jdbcMapsLedgerAndFiveIndexedExistenceChecks()throws Exception {
        var jdbc=mock(JdbcTemplate.class);var account=mock(ResultSet.class);var ledger=mock(ResultSet.class);
        when(account.getLong("id")).thenReturn(1L);when(account.getString("name")).thenReturn("Default Paper Portfolio");
        when(account.getString("execution_mode")).thenReturn("PAPER");
        when(account.getBigDecimal(anyString())).thenReturn(new BigDecimal("100000.00"));
        when(ledger.getLong("opening_cash")).thenReturn(10000000L);when(ledger.getLong("cash")).thenReturn(10000000L);
        when(ledger.getString("tail")).thenReturn("0".repeat(64));
        when(jdbc.query(anyString(),any(RowMapper.class))).thenAnswer(i->i.<String>getArgument(0).contains("paper_portfolio")?List.of(i.<RowMapper<?>>getArgument(1).mapRow(account,0)):List.of());
        when(jdbc.query(anyString(),any(RowMapper.class),eq(1L))).thenAnswer(i->{
            String sql=i.getArgument(0);assertTrue(sql.contains("WHERE portfolio_id=?"));
            if(sql.contains("paper_ledger_account"))return List.of(i.<RowMapper<?>>getArgument(1).mapRow(ledger,0));
            assertTrue(sql.contains("LIMIT 1"));return List.of();
        });
        assertEquals("ATTACHED_READ_ONLY",new PaperAccountReadService(jdbc).overview().ledger().status());
        assertEquals(9,mockingDetails(jdbc).getInvocations().size());
    }
}
