package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.math.BigDecimal;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperLedgerStore.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

class PaperLedgerStoreTest {
    static final class Db {
        final Connection c=mock(Connection.class);
        final List<String> writes=new ArrayList<>();
        final Map<String,List<Object>> params=new HashMap<>();
        boolean attached=true,legacy=true,positionCorrupt=false,orderCorrupt=false;
        long revision=0,cash=10000000,reserved=0,owned=0,shareReserve=0;
        Order order;String duplicate=null; Receipt receipt=null;String headPayload=null,tail="0".repeat(64);
        Db()throws Exception {
            when(c.createStatement()).thenReturn(mock(Statement.class));
            when(c.prepareStatement(anyString())).thenAnswer(inv->{
                String sql=inv.getArgument(0);PreparedStatement s=mock(PreparedStatement.class);
                var bindings=new ArrayList<Object>();params.put(sql,bindings);
                doAnswer(set->{int index=set.getArgument(0);while(bindings.size()<index)bindings.add(null);bindings.set(index-1,set.getArgument(1));return null;}).when(s).setObject(anyInt(),any());
                when(s.executeUpdate()).thenAnswer(q->{writes.add(sql);return 1;});
                when(s.executeQuery()).thenAnswer(q->{
                    if(sql.startsWith("SELECT current_cash"))return row(legacy?new Object[]{BigDecimal.valueOf(cash,2),"PAPER",true}:null);
                    if(sql.startsWith("SELECT cash"))return row(attached?new Object[]{cash,reserved,revision,revision==0?null:Timestamp.from(T),revision==0?null:encode(fixturePolicy()),tail,10000000L}:null);
                    if(sql.startsWith("SELECT receipt"))return row(new Object[]{encode(receipt),tail,"0".repeat(64),headPayload});
                    if(sql.startsWith("SELECT payload,receipt"))return row(duplicate==null?null:new Object[]{duplicate,encode(receipt)});
                    if(sql.startsWith("SELECT symbol"))return row(new Object[]{"FIXTURE"});
                    if(sql.startsWith("SELECT quantity"))return row(owned==0?null:new Object[]{owned,shareReserve,positionCorrupt?"bad":hash("1:1:"+owned+":"+shareReserve)});
                    if(sql.startsWith("SELECT instrument_id"))return row(order==null?null:new Object[]{1L,encode(order),orderCorrupt?"bad":hash("1:"+encode(order))});
                    throw new AssertionError(sql);
                });return s;
            });
        }
        static ResultSet row(Object[] fields)throws Exception {
            ResultSet r=mock(ResultSet.class);when(r.next()).thenReturn(fields!=null,false);
            if(fields!=null)for(int i=0;i<fields.length;i++){
                int at=i+1;Object v=fields[i];
                when(r.getString(at)).thenReturn(v==null?null:v.toString());
                when(r.getLong(at)).thenReturn(v instanceof Number n?n.longValue():0L);
                when(r.getBoolean(at)).thenReturn(Boolean.TRUE.equals(v));
                when(r.getBigDecimal(at)).thenReturn(v instanceof BigDecimal b?b:null);
                when(r.getTimestamp(at)).thenReturn(v instanceof Timestamp t?t:null);
            }return r;
        }
        PaperLedgerStore store(){return new PaperLedgerStore(()->c,fixturePolicy());}
        void approved(Side side,long quantity) {
            var cmd=PaperLedgerVerification.approve("a",0,"order",side,quantity);
            order=new Order(cmd.approval(),T,Status.OPEN,0,0);revision=1;reserved=reserve(order);
            if(side==Side.SELL){owned=10;shareReserve=quantity;}
            headPayload=encode(cmd);tail=hash("0".repeat(64)+"\n1\n"+headPayload+"\n"+cash+"\n"+reserved+"\nOPEN");
            receipt=new Receipt(1,cash,reserved,"OPEN",tail);
        }
    }
    @Test void approveReservesWithoutDebitingAndCommits()throws Exception {
        var db=new Db();var r=db.store().execute(1,PaperLedgerVerification.approve("a",0,"order",Side.BUY,10));
        assertEquals(101100,r.reservedCashPaise());assertEquals(10000000,r.cashPaise());verify(db.c).commit();verify(db.c,never()).rollback();
        assertTrue(db.writes.stream().anyMatch(s->s.startsWith("INSERT INTO paper_ledger_decision")));
        assertTrue(db.writes.stream().anyMatch(s->s.startsWith("UPDATE paper_portfolio")));
    }
    @Test void holdHasNoOrderOrCashReservation()throws Exception {
        var db=new Db();var r=db.store().execute(1,PaperLedgerVerification.approve("h",0,"hold",Side.HOLD,0));
        assertEquals("HOLD_NO_ORDER",r.orderStatus());assertEquals(0,r.reservedCashPaise());assertTrue(db.writes.stream().noneMatch(s->s.startsWith("INSERT INTO paper_ledger_order")));
    }
    @Test void partialBuyFillUsesExactMoney()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);var r=db.store().execute(1,PaperLedgerVerification.fill("f",1,"order","f",4,10));
        assertEquals(9959990,r.cashPaise());assertEquals(60690,r.reservedCashPaise());assertEquals("PARTIAL",r.orderStatus());
    }
    @Test void fullBuyFillReleasesUnusedFeeBudget()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);var r=db.store().execute(1,PaperLedgerVerification.fill("f",1,"order","f",10,10));
        assertEquals(9899990,r.cashPaise());assertEquals(0,r.reservedCashPaise());assertEquals("FILLED",r.orderStatus());
    }
    @Test void partialSellCreditsNetProceeds()throws Exception {
        var db=new Db();db.approved(Side.SELL,6);var r=db.store().execute(1,PaperLedgerVerification.fill("f",1,"order","f",2,10));
        assertEquals(10019990,r.cashPaise());assertEquals(0,r.reservedCashPaise());
        var values=db.params.entrySet().stream().filter(e->e.getKey().startsWith("INSERT INTO paper_ledger_position")).findFirst().orElseThrow().getValue();
        assertEquals(8L,values.get(2));assertEquals(4L,values.get(3));
    }
    @Test void cancelReleasesReservedCash()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);var r=db.store().execute(1,PaperLedgerVerification.terminal("c",1,"order",false));
        assertEquals(10000000,r.cashPaise());assertEquals(0,r.reservedCashPaise());assertEquals("CANCELLED",r.orderStatus());
    }
    @Test void expireDueReleasesCash()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);assertEquals("EXPIRED",db.store().execute(1,PaperLedgerVerification.terminal("e",1,"order",true)).orderStatus());
    }
    @Test void earlyExpiryRejectsBeforeWrites()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);assertThrows(IllegalArgumentException.class,()->db.store().execute(1,new Command("e",1,T,Kind.EXPIRE,0,null,null,null,null,"order")));
        assertTrue(db.writes.isEmpty());verify(db.c).rollback();
    }
    @Test void identicalRetryReturnsStoredReceiptWithoutWrites()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);var cmd=PaperLedgerVerification.approve("a",0,"order",Side.BUY,10);db.duplicate=encode(cmd);
        assertEquals(db.receipt,db.store().execute(1,cmd));assertTrue(db.writes.isEmpty());verify(db.c).commit();
    }
    @Test void conflictingRetryRollsBack()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);db.duplicate="different";assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.approve("a",0,"order",Side.BUY,10)));assertTrue(db.writes.isEmpty());verify(db.c).rollback();
    }
    @Test void staleRevisionFailsBeforeWrites()throws Exception {
        var db=new Db();db.approved(Side.BUY,10);assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.approve("new",0,"new",Side.BUY,1)));assertTrue(db.writes.isEmpty());
    }
    @Test void noAttachmentOrLegacyAccountNeverSeeds()throws Exception {
        for(boolean absent:List.of(true,false)){var db=new Db();db.attached=!absent;db.legacy=absent;assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.approve("a",0,"a",Side.BUY,1)));assertTrue(db.writes.isEmpty());verify(db.c).rollback();}
    }
    @Test void insufficientFundsRejectsWithoutWrites()throws Exception {
        var db=new Db();var p=new PaperLedgerStore(()->db.c,new Policy(5000,200,10000,20000000,50,100));
        assertThrows(IllegalArgumentException.class,()->p.execute(1,PaperLedgerVerification.approve("a",0,"a",Side.BUY,991)));assertTrue(db.writes.isEmpty());
    }
    @Test void unownedSellRejectsWithoutWrites()throws Exception {
        var db=new Db();assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.approve("a",0,"a",Side.SELL,1)));assertTrue(db.writes.isEmpty());
    }
    @Test void overfillAndFeeExcessRollback()throws Exception {
        for(boolean over:List.of(true,false)){var db=new Db();db.approved(Side.BUY,10);assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.fill("f",1,"order","f",over?11:1,over?0:101)));assertTrue(db.writes.isEmpty());}
    }
    @Test void corruptedOrderOrPositionBlocks()throws Exception {
        for(boolean corruptOrder:List.of(true,false)){var db=new Db();db.approved(Side.SELL,6);db.orderCorrupt=corruptOrder;db.positionCorrupt=!corruptOrder;assertThrows(IllegalArgumentException.class,()->db.store().execute(1,PaperLedgerVerification.fill("f",1,"order","f",1,0)));assertTrue(db.writes.isEmpty());}
    }
    @Test void rollbackRequestedAfterAnyWriteFailure()throws Exception {
        var db=new Db();var p=new PaperLedgerStore(()->db.c,fixturePolicy(),c->{throw new SQLException("before commit");});assertThrows(SQLException.class,()->p.execute(1,PaperLedgerVerification.approve("a",0,"a",Side.BUY,1)));assertFalse(db.writes.isEmpty());verify(db.c).rollback();verify(db.c,never()).commit();
    }
    @ParameterizedTest @ValueSource(longs={-1,5001}) void staleOrFutureQuoteRejected(long age) {
        var a=proposal("o",Side.BUY,1);Instant at=T.plusSeconds(10);var q=new Quote("FIXTURE",10000,at.minusMillis(age));var r=new RiskPermit(a.approvalId(),a.orderId(),at,true);
        assertThrows(IllegalArgumentException.class,()->validate(a,q,r,at,fixturePolicy()));
    }
    @Test void riskDenialAndMismatchedSymbolRejected() {
        var a=proposal("o",Side.BUY,1);assertThrows(IllegalArgumentException.class,()->validate(a,quote(10000),new RiskPermit(a.approvalId(),a.orderId(),T,false),T,fixturePolicy()));
        assertThrows(IllegalArgumentException.class,()->validate(a,new Quote("OTHER",10000,T),permit(a),T,fixturePolicy()));
    }
    @Test void riskOlderThanQuoteRejected() {
        var a=proposal("o",Side.BUY,1);assertThrows(IllegalArgumentException.class,()->validate(a,new Quote("FIXTURE",10000,T.plusMillis(1)),permit(a),T.plusMillis(1),fixturePolicy()));
    }
    @Test void priceOutsideZoneRejected() {var a=proposal("o",Side.BUY,1);assertThrows(IllegalArgumentException.class,()->validate(a,quote(10101),permit(a),T,fixturePolicy()));}
    @Test void commandSerializationPreservesIdentity() {var c=PaperLedgerVerification.approve("a",0,"order",Side.BUY,1);assertEquals(c,decode(encode(c),Command.class));}
    @Test void invalidEnvelopeAndSubMicrosecondClockRejected() {
        assertThrows(IllegalArgumentException.class,()->new Command("a",0,T,Kind.FILL,0,null,null,null,null,null));
        assertThrows(IllegalArgumentException.class,()->new Command("a",0,T.plusNanos(1),Kind.CANCEL,0,null,null,null,null,"order"));
    }
    @Test void transactionTimeoutAndLocksAreConfigured()throws Exception {
        var db=new Db();db.store().execute(1,PaperLedgerVerification.approve("a",0,"order",Side.BUY,1));
        verify(db.c).setAutoCommit(false);verify(db.c).setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
        assertTrue(db.params.keySet().stream().anyMatch(s->s.contains("paper_portfolio WHERE id=? FOR UPDATE")));
        assertTrue(db.params.keySet().stream().anyMatch(s->s.contains("paper_ledger_account WHERE portfolio_id=? FOR UPDATE")));
        assertTrue(db.params.keySet().stream().noneMatch(s->s.contains("ORDER BY")||s.contains("COUNT(*)")));
    }
    @Test void candidateMigrationNotOnAutomaticFlywayPath() {
        assertNotNull(getClass().getResource("/paper/ledger-v1.sql"));
        assertNull(getClass().getResource("/db/migration/ledger-v1.sql"));
        assertFalse(PaperLedgerStore.class.isAnnotationPresent(org.springframework.stereotype.Service.class));
    }
}
