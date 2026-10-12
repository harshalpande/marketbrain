package in.marketbrain.paper;

import java.sql.*;
import java.time.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalVerification.*;

/** Offline contracts and JDBC routing only. PostgreSQL permissions need the isolated spare suite. */
class PaperWriterVerificationTest {
    @ParameterizedTest @ValueSource(strings={"public","paper_verify_x","paper_verify_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; DROP TABLE x","../other",""})
    void refusesNonFixtureSchema(String value){assertThrows(IllegalArgumentException.class,()->PaperWriterVerification.candidateSql(value));}
    @Test void nullSchemaRejected(){assertThrows(IllegalArgumentException.class,()->PaperWriterVerification.schema(null));}
    @Test void invalidRoleAndEntrypointCannotReachJdbc(){
        String s="paper_verify_"+"a".repeat(32);
        assertThrows(IllegalArgumentException.class,()->PaperWriterVerification.writer(s,"postgres"));
        assertThrows(IllegalArgumentException.class,()->PaperWriterVerification.main(new String[]{"--live",s}));
        assertThrows(IllegalArgumentException.class,()->PaperWriterVerification.main(new String[]{"--prepare","public"}));
    }
    @Test void restrictedWriterCannotIssueBeforeIo(){
        var review=PaperApprovalReview.restrictedWriter(()->{throw new AssertionError("DB opened");},p->quote(),Clock.fixed(T,ZoneOffset.UTC),POLICY);
        assertThrows(IllegalArgumentException.class,()->review.issue(proposal("no",Side.BUY,1,0)));
    }
    @Test void privateChatDeniedBeforeIo(){
        var review=PaperApprovalReview.restrictedWriter(()->{throw new AssertionError("DB opened");},p->quote(),Clock.fixed(T,ZoneOffset.UTC),POLICY);
        assertThrows(IllegalArgumentException.class,()->review.process(new PaperApprovalReview.Callback("no",111,222,false,"a".repeat(43))));
    }
    @Test void scalarCommandBindsParametersAndEnforcesTimeout()throws Exception{
        Connection c=mock(Connection.class);PreparedStatement s=mock(PreparedStatement.class);ResultSet r=mock(ResultSet.class);
        when(c.prepareStatement("SELECT paper_review_lock(?,?,?)")).thenReturn(s);when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true);when(r.getBoolean(1)).thenReturn(true);
        PaperApprovalReview.writerCommand(c,"SELECT paper_review_lock(?,?,?)","a".repeat(64),111L,222L);
        verify(s).setObject(1,"a".repeat(64));verify(s).setObject(2,111L);verify(s).setObject(3,222L);verify(s).setQueryTimeout(10);verify(r).close();verify(s).close();
    }
    @ParameterizedTest @ValueSource(strings={"missing","false","null"})
    void scalarCommandFailsClosed(String failure)throws Exception{
        Connection c=mock(Connection.class);PreparedStatement s=mock(PreparedStatement.class);ResultSet r=mock(ResultSet.class);
        when(c.prepareStatement(anyString())).thenReturn(s);when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(!failure.equals("missing"));when(r.getBoolean(1)).thenReturn(!failure.equals("false"));when(r.wasNull()).thenReturn(failure.equals("null"));
        assertThrows(IllegalArgumentException.class,()->PaperApprovalReview.writerCommand(c,"SELECT paper_review_lock(?,?,?)","token",111L,222L));
    }
    @Test void sqlFailureIsPropagatedNotRetried()throws Exception{
        Connection c=mock(Connection.class);PreparedStatement s=mock(PreparedStatement.class);when(c.prepareStatement(anyString())).thenReturn(s);when(s.executeQuery()).thenThrow(new SQLException("denied","42501"));
        assertEquals("42501",assertThrows(SQLException.class,()->PaperApprovalReview.writerCommand(c,"SELECT paper_review_lock(?,?,?)","token",111L,222L)).getSQLState());verify(s,times(1)).executeQuery();
    }
    @Test void fixedSchemaSearchPathAndPublicRevocation()throws Exception{
        String sql=PaperWriterVerification.candidateSql("paper_verify_"+"a".repeat(32));
        assertFalse(sql.contains("__SCHEMA__"));assertEquals(2,sql.split("SECURITY DEFINER",-1).length-1);
        assertEquals(2,sql.split("SET search_path = pg_catalog,",-1).length-1);assertEquals(2,sql.split("FROM PUBLIC;",-1).length-1);
        assertTrue(sql.contains("pg_temp AS"));assertTrue(sql.contains("FOR UPDATE OF p"));assertTrue(sql.contains("FOR SHARE"));
        assertFalse(sql.contains("EXECUTE "));assertFalse(sql.contains("GRANT ALL"));
    }
    @Test void functionsOnlyWriteTerminalReview()throws Exception{
        String sql=PaperWriterVerification.candidateSql("paper_verify_"+"a".repeat(32));
        assertFalse(sql.contains("INSERT INTO"));assertFalse(sql.contains("DELETE FROM"));assertFalse(sql.contains("SET cash"));assertFalse(sql.contains("SET current_cash"));
        assertTrue(sql.contains("SET decided_token=p_token,callback_id=p_callback,receipt=p_receipt"));assertTrue(sql.contains("actionExecutionEnabled' IS DISTINCT FROM 'false'::jsonb"));assertTrue(sql.contains("v_proposal.receipt IS NOT NULL"));
    }
    @Test void noSpringActivationOrFlywayWriterMigration(){
        assertEquals(0,PaperWriterVerification.class.getAnnotations().length);assertEquals(0,PaperApprovalReview.class.getAnnotations().length);
        assertNull(getClass().getResource("/db/migration/V29__approval_writer.sql"));
    }
    @Test void restrictedProcessUsesCommandsNotDirectUpdatesOrBaseLocks()throws Exception{
        Connection c=mock(Connection.class);Statement setup=mock(Statement.class);when(c.createStatement()).thenReturn(setup);
        var queries=new java.util.ArrayList<String>();var p=proposal("bound",Side.BUY,1,0);String payload=PaperPersistenceEngineering.encode(p);
        when(c.prepareStatement(anyString())).thenAnswer(inv->{
            String sql=inv.getArgument(0);queries.add(sql);PreparedStatement s=mock(PreparedStatement.class);ResultSet r=mock(ResultSet.class);
            when(s.executeQuery()).thenReturn(r);when(r.next()).thenReturn(true,false);
            if(sql.startsWith("SELECT paper_review_"))when(r.getBoolean(1)).thenReturn(true);
            else if(sql.contains("FROM telegram_binding")){when(r.getLong(1)).thenReturn(111L);when(r.getLong(2)).thenReturn(222L);}
            else if(sql.contains("FROM paper_approval_token")){
                when(r.getString(1)).thenReturn(payload);when(r.getString(2)).thenReturn(PaperLedgerStore.hash(payload));when(r.getString(3)).thenReturn(PaperApprovalReview.identity(111,222));
                when(r.getLong(4)).thenReturn(1L);when(r.getLong(5)).thenReturn(1L);when(r.getLong(6)).thenReturn(0L);when(r.getString(7)).thenReturn("ACCEPT");when(r.getString(10)).thenReturn(PaperLedgerStore.hash(PaperPersistenceEngineering.encode(POLICY)));
            } else if(sql.contains("FROM paper_portfolio"))when(r.getBigDecimal(1)).thenReturn(new java.math.BigDecimal("100000"));
            else if(sql.contains("FROM paper_ledger_account")){when(r.getLong(1)).thenReturn(10000000L);when(r.getLong(4)).thenReturn(10000000L);when(r.getString(7)).thenReturn("0".repeat(64));}
            else if(sql.contains("FROM paper_ledger_position"))when(r.next()).thenReturn(false);
            else if(sql.contains("FROM instrument"))when(r.getString(1)).thenReturn("FIXTURE");
            else throw new AssertionError("Unexpected query: "+sql);
            return s;
        });
        var review=PaperApprovalReview.restrictedWriter(()->c,ignored->quote(),Clock.fixed(T,ZoneOffset.UTC),POLICY);
        assertEquals("ACCEPTED_EXECUTION_BLOCKED",review.process(new PaperApprovalReview.Callback("cb",111,222,true,"a".repeat(43))).status());
        assertTrue(queries.contains("SELECT paper_review_lock(?,?,?)"));assertTrue(queries.contains("SELECT paper_review_record(?,?,?,?,?)"));
        assertTrue(queries.stream().noneMatch(q->q.contains("FOR UPDATE")||q.contains("FOR SHARE")||q.startsWith("UPDATE")||q.startsWith("INSERT")));
        verify(c,times(2)).commit();verify(c,never()).rollback();
    }
}
