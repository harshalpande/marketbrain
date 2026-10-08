package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.*;

class PaperPersistenceEngineeringTest {
    static final String SCHEMA="paper_verify_"+"a".repeat(32);
    static Command approval(){return PaperPersistenceVerification.approve("a",proposal("buy",Side.BUY,10));}
    static final class Fixture {
        final Connection connection=mock(Connection.class);
        final Statement statement=mock(Statement.class);
        final PreparedStatement header=mock(PreparedStatement.class),commands=mock(PreparedStatement.class),insert=mock(PreparedStatement.class),update=mock(PreparedStatement.class);
        final ResultSet headerRows=mock(ResultSet.class),commandRows=mock(ResultSet.class);
        final List<Command> saved;
        Fixture(Command... saved) throws Exception {
            this.saved=List.of(saved);
            when(connection.createStatement()).thenReturn(statement);
            when(connection.prepareStatement(startsWith("SELECT policy"))).thenReturn(header);
            when(connection.prepareStatement(startsWith("SELECT seq"))).thenReturn(commands);
            when(connection.prepareStatement(startsWith("INSERT"))).thenReturn(insert);
            when(connection.prepareStatement(startsWith("UPDATE"))).thenReturn(update);
            when(header.executeQuery()).thenReturn(headerRows);when(commands.executeQuery()).thenReturn(commandRows);
            when(headerRows.next()).thenReturn(true,false);when(headerRows.getString(1)).thenReturn(encode(fixturePolicy()));when(headerRows.getLong(2)).thenReturn((long)saved.length);
            var clock=new FixtureClock(Instant.EPOCH);var account=new Account(fixturePolicy(),clock);String previous="0".repeat(64);
            List<String[]> rows=new ArrayList<>();int index=0;
            for(Command cmd:saved){apply(account,clock,cmd);String payload=encode(cmd);String hash=chain(++index,previous,payload);rows.add(new String[]{cmd.id(),payload,previous,hash});previous=hash;}
            when(headerRows.getString(3)).thenReturn(previous);when(headerRows.getString(4)).thenReturn(encode(account.audit()));
            int[] position={-1};when(commandRows.next()).thenAnswer(i->++position[0]<rows.size());when(commandRows.getLong(1)).thenAnswer(i->(long)position[0]+1);
            when(commandRows.getString(anyInt())).thenAnswer(i->rows.get(position[0])[(int)i.getArgument(0)-2]);
            when(update.executeUpdate()).thenReturn(1);
        }
        PaperPersistenceEngineering repo(){return new PaperPersistenceEngineering(()->connection,SCHEMA,fixturePolicy());}
    }
    @Test void rejectsProductionSchemaBeforeOpeningConnection(){assertThrows(IllegalArgumentException.class,()->new PaperPersistenceEngineering(()->{throw new AssertionError();},"public",fixturePolicy()));}
    @Test void rejectsInjectedSchema(){assertThrows(IllegalArgumentException.class,()->new PaperPersistenceEngineering(()->null,SCHEMA+";DROP SCHEMA public",fixturePolicy()));}
    @Test void commandCodecPreservesExactNanosecondTiming(){var c=new Command("x",T.plusNanos(5),Kind.EXPIRE,null,null,null,null,null);assertEquals(c,decode(encode(c)));}
    @Test void rejectsIrrelevantCommandFields(){assertThrows(IllegalArgumentException.class,()->new Command("x",T,Kind.CANCEL,null,null,quote(10000),null,"buy"));}
    @Test void rejectsMissingFillFields(){assertThrows(IllegalArgumentException.class,()->new Command("x",T,Kind.FILL,null,null,null,null,null));}
    @Test void checksumBindsVersionSequencePreviousAndPayload(){String a=chain(1,"0".repeat(64),"hello");assertNotEquals(a,chain(2,"0".repeat(64),"hello"));assertNotEquals(a,chain(1,"1".repeat(64),"hello"));assertNotEquals(a,chain(1,"0".repeat(64),"Hello"));assertEquals(64,a.length());}
    @Test void initialReadReconcilesWithoutWriting() throws Exception{var f=new Fixture();var r=f.repo().inspect();assertEquals(10000000,r.audit().account().cashPaise());verify(f.connection).commit();verify(f.insert,never()).executeUpdate();}
    @Test void approvalAtomicallyAppendsAndProjects() throws Exception{var f=new Fixture();var r=f.repo().execute(approval());assertEquals(1,r.revision());assertEquals(101100,r.audit().account().reservedCashPaise());var order=inOrder(f.insert,f.update,f.connection);order.verify(f.insert).executeUpdate();order.verify(f.update).executeUpdate();order.verify(f.connection).commit();}
    @Test void configuredTransactionTimeoutsAndSynchronousCommit() throws Exception{var f=new Fixture();f.repo().inspect();verify(f.statement).execute("SET LOCAL lock_timeout='3s'");verify(f.statement).execute("SET LOCAL statement_timeout='10s'");verify(f.statement).execute("SET LOCAL synchronous_commit=on");verify(f.connection).setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);}
    @Test void updateFailureRollsBackAppend() throws Exception{var f=new Fixture();when(f.update.executeUpdate()).thenThrow(new SQLException("failure"));assertThrows(SQLException.class,()->f.repo().execute(approval()));verify(f.connection).rollback();verify(f.connection,never()).commit();}
    @Test void optimisticRevisionMismatchRollsBack() throws Exception{var f=new Fixture();when(f.update.executeUpdate()).thenReturn(0);assertThrows(IllegalArgumentException.class,()->f.repo().execute(approval()));verify(f.connection).rollback();}
    @Test void injectedFailureBeforeCommitRollsBack() throws Exception{var f=new Fixture();var p=new PaperPersistenceEngineering(()->f.connection,SCHEMA,fixturePolicy(),c->{throw new SQLException("stop");});assertThrows(SQLException.class,()->p.execute(approval()));verify(f.connection).rollback();verify(f.connection,never()).commit();}
    @Test void unknownCommitOutcomeIsNotAutomaticallyRetried() throws Exception{var f=new Fixture();doThrow(new SQLException("connection lost")).when(f.connection).commit();assertThrows(SQLException.class,()->f.repo().execute(approval()));verify(f.insert,times(1)).executeUpdate();verify(f.connection,times(1)).commit();}
    @Test void duplicateAfterReopenReturnsWithoutWrite() throws Exception{var f=new Fixture(approval());var r=f.repo().execute(approval());assertTrue(r.duplicate());assertEquals(1,r.revision());verify(f.insert,never()).executeUpdate();}
    @Test void conflictingIdFailsWithoutWrite() throws Exception{var f=new Fixture(approval());assertThrows(IllegalArgumentException.class,()->f.repo().execute(PaperPersistenceVerification.approve("a",proposal("buy",Side.BUY,11))));verify(f.insert,never()).executeUpdate();verify(f.connection).rollback();}
    @Test void savedProjectionMismatchStopsAllWrites() throws Exception{var f=new Fixture();when(f.headerRows.getString(4)).thenReturn("{}");assertThrows(IllegalArgumentException.class,()->f.repo().execute(approval()));verify(f.insert,never()).executeUpdate();}
    @Test void savedTailMismatchStopsAllWrites() throws Exception{var f=new Fixture();when(f.headerRows.getString(3)).thenReturn("f".repeat(64));assertThrows(IllegalArgumentException.class,()->f.repo().inspect());}
    @Test void policyMismatchStopsReplay() throws Exception{var f=new Fixture();when(f.headerRows.getString(1)).thenReturn("{}");assertThrows(IllegalArgumentException.class,()->f.repo().inspect());}
    @Test void missingAccountDoesNotInitialize() throws Exception{var f=new Fixture();when(f.headerRows.next()).thenReturn(false);assertThrows(IllegalArgumentException.class,()->f.repo().inspect());verify(f.statement,never()).execute(startsWith("CREATE"));}
    @Test void sequenceGapRejected() throws Exception{var f=new Fixture(approval());when(f.commandRows.getLong(1)).thenReturn(2L);assertThrows(IllegalArgumentException.class,()->f.repo().inspect());}
    @Test void recordCorruptionRejected() throws Exception{var f=new Fixture(approval());doReturn("f".repeat(64)).when(f.commandRows).getString(5);assertThrows(IllegalArgumentException.class,()->f.repo().inspect());}
    @Test void partialFillReplaysSameAccounting() throws Exception{var f=new Fixture(approval(),PaperPersistenceVerification.fill("f","f1","buy",4,10));var r=f.repo().inspect();assertEquals(9959990,r.audit().account().cashPaise());assertEquals(60690,r.audit().account().reservedCashPaise());assertEquals(4L,r.audit().account().holdings().get("FIXTURE"));}
    @Test void noOpCommandStillAdvancesClockFence() throws Exception{var f=new Fixture(new Command("x",T.plusSeconds(1),Kind.EXPIRE,null,null,null,null,null));assertThrows(IllegalArgumentException.class,()->f.repo().execute(approval()));}
    @Test void schemaCreationIsExplicitAndNonDestructive() throws Exception{var f=new Fixture();f.repo().initialize();verify(f.statement).execute("CREATE SCHEMA "+SCHEMA);verify(f.statement,never()).execute(contains("DROP"));verify(f.connection).commit();}
}
