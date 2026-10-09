package in.marketbrain.paper;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.sql.*;
import java.time.Duration;
import java.time.Instant;
import java.util.Objects;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Candidate application ledger. No bean, controller, initializer, provider or broker access.
 * All command/risk inputs are INTERNAL evidence; authenticated authority is a separate release gate. */
public final class PaperLedgerStore {
    public static final String VERSION = "PAPER_APPLICATION_LEDGER_V1";
    public enum Kind { APPROVE, FILL, CANCEL, EXPIRE }
    public record Command(String id, long expectedRevision, Instant at, Kind kind, long instrumentId,
                          Approval approval, Fill fill, Quote quote, RiskPermit permit, String orderId) {
        public Command {
            token(id); require(expectedRevision >= 0, "Invalid revision"); Objects.requireNonNull(at); Objects.requireNonNull(kind);
            require(at.getNano() % 1000 == 0, "Use PostgreSQL microsecond timestamps");
            switch(kind) {
                case APPROVE -> require(instrumentId > 0 && approval != null && fill == null && quote != null && permit != null && orderId == null, "Approval payload");
                case FILL -> require(instrumentId == 0 && approval == null && fill != null && quote != null && permit != null && orderId == null, "Fill payload");
                case CANCEL, EXPIRE -> { token(orderId); require(instrumentId == 0 && approval == null && fill == null && quote == null && permit == null, "Terminal payload"); }
            }
        }
    }
    public record Receipt(long revision, long cashPaise, long reservedCashPaise, String orderStatus, String tailHash) {}
    record Balance(long cash, long reserved, long revision, Instant lastAt, String policy, String tail, long opening) {}
    record Position(long quantity, long reserved) {}
    record StoredOrder(long instrumentId, Order order) {}
    @FunctionalInterface public interface Connections { Connection open() throws SQLException; }
    @FunctionalInterface interface BeforeCommit { void run(Connection c) throws SQLException; }
    private final Connections connections;
    private final Policy policy;
    private final BeforeCommit beforeCommit;

    public PaperLedgerStore(Connections connections, Policy policy) { this(connections, policy, c -> {}); }
    PaperLedgerStore(Connections connections, Policy policy, BeforeCommit hook) {
        this.connections=Objects.requireNonNull(connections); this.policy=Objects.requireNonNull(policy); this.beforeCommit=hook;
    }

    /** Indexed projections, not lifetime replay. IDs remain permanently in append-only tables. */
    public Receipt execute(long portfolioId, Command command) throws SQLException {
        require(portfolioId > 0, "Portfolio required"); Objects.requireNonNull(command);
        String payload=encode(command); require(payload.getBytes(java.nio.charset.StandardCharsets.UTF_8).length<=16384,"Command too large");
        try(Connection c=connections.open()) {
            c.setAutoCommit(false); c.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
            try {
                configure(c);
                // Same lock order for every command; legacy balance and ledger projection commit together.
                long legacyCash=legacyCash(c,portfolioId);
                Balance b=balance(c,portfolioId); require(legacyCash==b.cash,"Legacy cash diverged; manual review required");
                require(b.policy==null || b.policy.equals(encode(policy)),"Policy mismatch");
                verifyHead(c,portfolioId,b);
                try(var s=statement(c,"SELECT payload,receipt FROM paper_ledger_command WHERE portfolio_id=? AND command_id=?",portfolioId,command.id);var r=s.executeQuery()) {
                    if(r.next()) {require(payload.equals(r.getString(1)),"Command ID payload conflict");Receipt receipt=decode(r.getString(2),Receipt.class);c.commit();return receipt;}
                }
                require(command.expectedRevision==b.revision,"Stale account revision");
                require(b.lastAt==null || !command.at.isBefore(b.lastAt),"Clock rollback");
                long cash=b.cash,reserved=b.reserved; String status;
                if(command.kind==Kind.APPROVE) {
                    Approval a=command.approval; validate(a,command.quote,command.permit,command.at,policy);
                    require(command.at.isBefore(a.expiresAt()),"Approval expired");
                    try(var s=statement(c,"SELECT symbol FROM instrument WHERE id=? AND active=TRUE",command.instrumentId);var r=s.executeQuery()) {
                        require(r.next() && r.getString(1).equals(a.symbol()),"Instrument identity mismatch");
                    }
                    Position p=position(c,portfolioId,command.instrumentId);
                    long budget=reserve(new Order(a,command.at,Status.OPEN,0,0));
                    if(a.side()==Side.BUY) {reserved=Math.addExact(reserved,budget);require(reserved<=cash,"Insufficient cash");}
                    if(a.side()==Side.SELL) {require(a.quantity()<=p.quantity-p.reserved,"Insufficient owned shares");writePosition(c,portfolioId,command.instrumentId,p.quantity,Math.addExact(p.reserved,a.quantity()));}
                    update(c,"INSERT INTO paper_ledger_decision VALUES (?,?,?,?)",portfolioId,a.approvalId(),a.orderId(),encode(a));
                    if(a.side()==Side.HOLD) status="HOLD_NO_ORDER";
                    else {Order order=new Order(a,command.at,Status.OPEN,0,0);writeOrder(c,portfolioId,command.instrumentId,order,true);status="OPEN";}
                } else {
                    StoredOrder stored=order(c,portfolioId,command.kind==Kind.FILL?command.fill.orderId():command.orderId);
                    Order old=stored.order; Approval a=old.approval(); require(old.active(),"Order terminal");
                    require(!command.at.isBefore(old.approvedAt()),"Command predates approval");
                    Position p=position(c,portfolioId,stored.instrumentId); Order next;
                    if(command.kind==Kind.FILL) {
                        Fill f=command.fill;validate(a,command.quote,command.permit,command.at,policy);price(a,f.pricePaise(),policy);
                        require(command.at.isBefore(a.expiresAt()),"Order expired");
                        require(!command.quote.observedAt().isBefore(old.approvedAt()) && !command.permit.assessedAt().isBefore(old.approvedAt()),"Fill evidence predates approval");
                        require(f.quantity()<=old.remaining(),"Overfill");
                        require(a.side()==Side.BUY? f.pricePaise()>=command.quote.pricePaise():f.pricePaise()<=command.quote.pricePaise(),"Optimistic fill");
                        long fees=Math.addExact(old.feesPaidPaise(),f.feePaise());require(fees<=a.feeBudgetPaise(),"Fee budget exceeded");
                        long notional=Math.multiplyExact(f.quantity(),f.pricePaise());
                        long quantity=p.quantity,shareReserve=p.reserved;
                        if(a.side()==Side.BUY) {cash=Math.subtractExact(cash,Math.addExact(notional,f.feePaise()));quantity=Math.addExact(quantity,f.quantity());}
                        else {require(f.feePaise()<=notional,"Fees exceed proceeds");cash=Math.addExact(cash,Math.subtractExact(notional,f.feePaise()));quantity=Math.subtractExact(quantity,f.quantity());shareReserve=Math.subtractExact(shareReserve,f.quantity());}
                        long filled=Math.addExact(old.filledQuantity(),f.quantity());
                        next=new Order(a,old.approvedAt(),filled==a.quantity()?Status.FILLED:Status.PARTIAL,filled,fees);
                        update(c,"INSERT INTO paper_ledger_fill VALUES (?,?,?,?)",portfolioId,f.fillId(),f.orderId(),encode(f));
                        writePosition(c,portfolioId,stored.instrumentId,quantity,shareReserve);
                    } else {
                        if(command.kind==Kind.EXPIRE) require(!command.at.isBefore(a.expiresAt()),"Expiry not due");
                        next=new Order(a,old.approvedAt(),command.kind==Kind.EXPIRE?Status.EXPIRED:Status.CANCELLED,old.filledQuantity(),old.feesPaidPaise());
                        if(a.side()==Side.SELL) writePosition(c,portfolioId,stored.instrumentId,p.quantity,Math.subtractExact(p.reserved,old.remaining()));
                    }
                    reserved=Math.addExact(Math.subtractExact(reserved,reserve(old)),reserve(next));
                    writeOrder(c,portfolioId,stored.instrumentId,next,false);status=next.status().name();
                }
                require(cash>=0 && reserved>=0 && reserved<=cash,"Cash invariant");
                long revision=Math.addExact(b.revision,1);
                String tail=hash(b.tail+"\n"+revision+"\n"+payload+"\n"+cash+"\n"+reserved+"\n"+status);
                Receipt receipt=new Receipt(revision,cash,reserved,status,tail);
                update(c,"INSERT INTO paper_ledger_command VALUES (?,?,?,?,?,?,?)",portfolioId,command.id,revision,payload,encode(receipt),b.tail,tail);
                require(update(c,"UPDATE paper_ledger_account SET cash=?,reserved=?,revision=?,last_at=?,policy=?,tail=? WHERE portfolio_id=? AND revision=?",cash,reserved,revision,Timestamp.from(command.at),encode(policy),tail,portfolioId,b.revision)==1,"Revision changed");
                require(update(c,"UPDATE paper_portfolio SET current_cash=?,updated_at=? WHERE id=? AND current_cash=?",BigDecimal.valueOf(cash,2),Timestamp.from(command.at),portfolioId,BigDecimal.valueOf(legacyCash,2))==1,"Legacy balance changed");
                beforeCommit.run(c);c.commit();return receipt;
            } catch(Exception e) {try{c.rollback();}catch(SQLException rollback){e.addSuppressed(rollback);}if(e instanceof SQLException sql)throw sql;if(e instanceof RuntimeException runtime)throw runtime;throw new SQLException(e);}
        }
    }

    static void validate(Approval a, Quote q, RiskPermit r, Instant at, Policy policy) {
        require(!at.isBefore(a.createdAt()),"Proposal future dated");
        require(r!=null && r.allowed() && r.approvalId().equals(a.approvalId()) && r.orderId().equals(a.orderId()),"Risk permit mismatch");
        require(q!=null && q.symbol().equals(a.symbol()),"Quote mismatch");
        for(Instant time: new Instant[]{q.observedAt(),r.assessedAt()}) require(!time.isAfter(at) && !time.isBefore(a.createdAt()) && Duration.between(time,at).compareTo(Duration.ofMillis(policy.maxQuoteAgeMillis()))<=0,"Stale or future evidence");
        require(!r.assessedAt().isBefore(q.observedAt()),"Risk predates quote");price(a,q.pricePaise(),policy);
        require(a.quantity()<=policy.maxQuantity() && Math.multiplyExact(a.quantity(),a.zoneMaxPaise())<=policy.maxOrderNotionalPaise(),"Order policy limit");
    }
    static long reserve(Order o) {return o.active() && o.approval().side()==Side.BUY?Math.addExact(Math.multiplyExact(o.remaining(),o.approval().zoneMaxPaise()),Math.subtractExact(o.approval().feeBudgetPaise(),o.feesPaidPaise())):0;}
    private static void price(Approval a,long price,Policy policy) {
        require(price>=a.zoneMinPaise() && price<=a.zoneMaxPaise(),"Price zone");
        require(BigInteger.valueOf(price).subtract(BigInteger.valueOf(a.referencePaise())).abs().multiply(BigInteger.valueOf(10000))
                .compareTo(BigInteger.valueOf(a.referencePaise()).multiply(BigInteger.valueOf(policy.maxSlippageBps())))<=0,"Slippage");
    }
    private static long legacyCash(Connection c,long id)throws SQLException {
        try(var s=statement(c,"SELECT current_cash,execution_mode::text,active FROM paper_portfolio WHERE id=? FOR UPDATE",id);var r=s.executeQuery()) {
            require(r.next() && "PAPER".equals(r.getString(2)) && r.getBoolean(3),"Active paper account missing");return r.getBigDecimal(1).movePointRight(2).longValueExact();
        }
    }
    private static Balance balance(Connection c,long id)throws SQLException {
        try(var s=statement(c,"SELECT cash,reserved,revision,last_at,policy,tail,opening_cash FROM paper_ledger_account WHERE portfolio_id=? FOR UPDATE",id);var r=s.executeQuery()) {
            require(r.next(),"Account not attached; never reseed");return new Balance(r.getLong(1),r.getLong(2),r.getLong(3),r.getTimestamp(4)==null?null:r.getTimestamp(4).toInstant(),r.getString(5),r.getString(6),r.getLong(7));
        }
    }
    private static void verifyHead(Connection c,long id,Balance b)throws SQLException {
        if(b.revision==0) {require(b.cash==b.opening && b.tail.equals("0".repeat(64)) && b.reserved==0 && b.policy==null && b.lastAt==null,"Opening projection mismatch");return;}
        try(var s=statement(c,"SELECT receipt,hash,previous_hash,payload FROM paper_ledger_command WHERE portfolio_id=? AND revision=?",id,b.revision);var r=s.executeQuery()) {
            require(r.next(),"Journal head missing");Receipt head=decode(r.getString(1),Receipt.class);
            require(head.revision==b.revision && head.cashPaise==b.cash && head.reservedCashPaise==b.reserved && head.tailHash.equals(b.tail) && b.tail.equals(r.getString(2)),"Journal projection mismatch");
            require(hash(r.getString(3)+"\n"+b.revision+"\n"+r.getString(4)+"\n"+b.cash+"\n"+b.reserved+"\n"+head.orderStatus).equals(b.tail),"Journal head hash mismatch");
        }
    }
    private static Position position(Connection c,long id,long instrument)throws SQLException {
        try(var s=statement(c,"SELECT quantity,reserved,hash FROM paper_ledger_position WHERE portfolio_id=? AND instrument_id=?",id,instrument);var r=s.executeQuery()) {
            if(!r.next())return new Position(0,0);
            require(hash(id+":"+instrument+":"+r.getLong(1)+":"+r.getLong(2)).equals(r.getString(3)),"Position projection mismatch");
            return new Position(r.getLong(1),r.getLong(2));
        }
    }
    private static void writePosition(Connection c,long id,long instrument,long quantity,long reserved)throws SQLException {
        require(quantity>=0 && reserved>=0 && reserved<=quantity,"Owned shares invariant");
        update(c,"INSERT INTO paper_ledger_position VALUES (?,?,?,?,?) ON CONFLICT (portfolio_id,instrument_id) DO UPDATE SET quantity=EXCLUDED.quantity,reserved=EXCLUDED.reserved,hash=EXCLUDED.hash",id,instrument,quantity,reserved,hash(id+":"+instrument+":"+quantity+":"+reserved));
    }
    private static StoredOrder order(Connection c,long id,String order)throws SQLException {
        try(var s=statement(c,"SELECT instrument_id,payload,hash FROM paper_ledger_order WHERE portfolio_id=? AND order_id=?",id,order);var r=s.executeQuery()) {
            require(r.next(),"Order missing");require(hash(r.getLong(1)+":"+r.getString(2)).equals(r.getString(3)),"Order projection mismatch");
            Order value=decode(r.getString(2),Order.class);require(value.approval().orderId().equals(order),"Order identity mismatch");return new StoredOrder(r.getLong(1),value);
        }
    }
    private static void writeOrder(Connection c,long id,long instrument,Order order,boolean insert)throws SQLException {
        String payload=encode(order);
        if(insert)update(c,"INSERT INTO paper_ledger_order VALUES (?,?,?,?,?)",id,order.approval().orderId(),instrument,payload,hash(instrument+":"+payload));
        else require(update(c,"UPDATE paper_ledger_order SET payload=?,hash=? WHERE portfolio_id=? AND order_id=?",payload,hash(instrument+":"+payload),id,order.approval().orderId())==1,"Order disappeared");
    }
    private static final com.fasterxml.jackson.databind.ObjectMapper JSON=com.fasterxml.jackson.databind.json.JsonMapper.builder().findAndAddModules().build();
    static <T>T decode(String value,Class<T> type) {try{return JSON.readValue(value,type);}catch(Exception e){throw new IllegalArgumentException("Invalid saved ledger record",e);}}
    static String hash(String value) {try{return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    static PreparedStatement statement(Connection c,String sql,Object...args)throws SQLException {PreparedStatement s=c.prepareStatement(sql);s.setQueryTimeout(10);for(int i=0;i<args.length;i++)s.setObject(i+1,args[i]);return s;}
    static int update(Connection c,String sql,Object...args)throws SQLException {try(var s=statement(c,sql,args)){return s.executeUpdate();}}
    private static void configure(Connection c)throws SQLException {try(var s=c.createStatement()){s.execute("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='10s'; SET LOCAL idle_in_transaction_session_timeout='15s'; SET LOCAL synchronous_commit=on");}}
    private static void token(String value) {require(value!=null && value.matches("[A-Za-z0-9_.:-]{1,100}"),"Invalid identifier");}
    private static void require(boolean value,String reason){if(!value)throw new IllegalArgumentException(reason);}
}
