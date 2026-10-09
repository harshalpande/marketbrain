package in.marketbrain.paper;

import java.security.SecureRandom;
import java.sql.*;
import java.time.*;
import java.util.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperLedgerStore.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Internal approval review, NOT an execution authority or Spring component.
 * Telegram transport authentication and a bounded server-owned QuoteSource must be wired separately.
 * The read-only portal credential cannot issue proposals or authorize this class. */
public final class PaperApprovalReview {
    public static final String VERSION="PAPER_APPROVAL_REVIEW_V1";
    public record Proposal(String id,long portfolioId,long instrumentId,long expectedRevision,
                           long userId,long chatId,Approval terms,String policyId) {
        public Proposal { tokenId(id); tokenId(policyId); Objects.requireNonNull(terms);
            require(portfolioId>0 && instrumentId>0 && expectedRevision>=0 && userId>0 && chatId>0,"Invalid proposal identity");
            require(id.equals(terms.approvalId()),"Proposal/approval mismatch"); }
    }
    public record Callback(String id,long userId,long chatId,boolean privateChat,String rawToken) {
        public Callback {tokenId(id);require(id.length()<=100,"Callback too long");require(rawToken!=null && rawToken.matches("[A-Za-z0-9_-]{43}"),"Invalid token");}
    }
    public record Tokens(String accept,String reject) {}
    public record MarketQuote(long instrumentId,String symbol,String provider,long pricePaise,Instant observedAt,Instant receivedAt) {}
    public record Snapshot(long revision,long cash,long reserved,long owned,long reservedShares,boolean consistent) {}
    public record PolicyVersion(String id,String provider,Policy limits,Duration maxProposalLifetime) {
        public PolicyVersion {tokenId(id);tokenId(provider);Objects.requireNonNull(limits);Objects.requireNonNull(maxProposalLifetime);
            require(!maxProposalLifetime.isNegative()&&!maxProposalLifetime.isZero()&&maxProposalLifetime.compareTo(Duration.ofMinutes(10))<=0,"Invalid lifetime");}
    }
    public record Receipt(String version,String status,String proposalId,long accountRevision,String policyId,
                          Instant assessedAt,String quoteHash,boolean actionExecutionEnabled) {}
    @FunctionalInterface public interface QuoteSource { MarketQuote latest(Proposal proposal) throws Exception; }
    private record Pending(Proposal proposal,String action,String policyHash,String decidedToken,Receipt receipt) {}
    private final Connections connections; private final QuoteSource quotes; private final Clock clock; private final PolicyVersion policy;
    private final SecureRandom random=new SecureRandom();
    public PaperApprovalReview(Connections connections, QuoteSource quotes, Clock clock,PolicyVersion policy) {
        this.connections=Objects.requireNonNull(connections);this.quotes=Objects.requireNonNull(quotes);
        this.clock=Objects.requireNonNull(clock);this.policy=Objects.requireNonNull(policy);
    }
    /** Internal proposal publisher only. Raw tokens returned once; persistence contains hashes only. */
    public Tokens issue(Proposal p)throws SQLException {
        validateIssue(p);
        try(Connection c=connections.open()) {begin(c);try {
            Tokens tokens=issue(c,p);c.commit();return tokens;
        }catch(Exception e){rollback(c,e);throw e;}}
    }
    /** Shared transaction for atomic proposal + encrypted delivery enqueue. Never called by HTTP. */
    Tokens issue(Connection c,Proposal p)throws SQLException {
        validateIssue(p);
        String accept=newToken(),reject=newToken(),payload=encode(p);
        binding(c,p.userId,p.chatId,true);
        var snapshot=snapshot(c,p,true);require(snapshot.consistent&&snapshot.revision==p.expectedRevision,"Account changed or inconsistent");
        update(c,"INSERT INTO paper_approval_proposal(id,portfolio_id,instrument_id,recipient_hash,expected_revision,payload,payload_hash,policy_hash) VALUES(?,?,?,?,?,?,?,?)",
                p.id,p.portfolioId,p.instrumentId,identity(p.userId,p.chatId),p.expectedRevision,payload,hash(payload),hash(encode(policy)));
        update(c,"INSERT INTO paper_approval_token VALUES(?,?,?)",hash(accept),p.id,"ACCEPT");
        update(c,"INSERT INTO paper_approval_token VALUES(?,?,?)",hash(reject),p.id,"REJECT");
        return new Tokens(accept,reject);
    }
    private void validateIssue(Proposal p) {
        Instant now=clock.instant();
        require(!now.isBefore(p.terms.createdAt())&&now.isBefore(p.terms.expiresAt()),"Proposal outside validity");
        require(p.policyId.equals(policy.id)&&Duration.between(p.terms.createdAt(),p.terms.expiresAt()).compareTo(policy.maxProposalLifetime)<=0,"Proposal policy mismatch");
        require(p.terms.side()!=Side.HOLD,"HOLD has no action tokens");
    }
    /** Callback identity must come from the authenticated private transport, not HTTP body fields.
     * First authenticate without a network call; load quote without DB locks; recheck under locks. */
    public Receipt process(Callback cb)throws SQLException {
        require(cb.privateChat,"Private chat required");String tokenHash=hash(cb.rawToken);
        Pending initial;
        try(Connection c=connections.open()) {begin(c);try {binding(c,cb.userId,cb.chatId,false);initial=pending(c,tokenHash,cb,false);c.commit();}catch(Exception e){rollback(c,e);throw e;}}
        MarketQuote q=null;
        if(initial.receipt==null && initial.action.equals("ACCEPT") && clock.instant().isBefore(initial.proposal.terms.expiresAt())) {
            try{q=quotes.latest(initial.proposal);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new SQLException("Quote review interrupted",interrupted);}catch(Exception unavailable){q=null;}
        }
        try(Connection c=connections.open()) {begin(c);try {
            binding(c,cb.userId,cb.chatId,true);
            Pending current=pending(c,tokenHash,cb,true);
            if(current.receipt!=null) {require(current.decidedToken.equals(tokenHash),"Proposal already decided by another action");c.commit();return current.receipt;}
            Proposal p=current.proposal;
            Snapshot account=snapshot(c,p,true);Instant now=clock.instant();
            String status=now.isBefore(p.terms.createdAt())?"CLOCK_INVALID":!now.isBefore(p.terms.expiresAt())?"EXPIRED"
                    :current.action.equals("REJECT")?"REJECTED":!current.policyHash.equals(hash(encode(policy)))?"POLICY_CHANGED":evaluate(p,q,account,now,policy);
            Receipt result=new Receipt(VERSION,status,p.id,account.revision,policy.id,now,q==null?null:hash(encode(q)),false);
            require(update(c,"UPDATE paper_approval_proposal SET decided_token=?,callback_id=?,receipt=? WHERE id=? AND receipt IS NULL",tokenHash,cb.id,encode(result),p.id)==1,"Decision raced");
            c.commit();return result;
        }catch(Exception e){rollback(c,e);throw e;}}
    }
    static String evaluate(Proposal p,MarketQuote q,Snapshot s,Instant now,PolicyVersion policy) {
        if(!s.consistent)return "ACCOUNT_INCONSISTENT";
        if(s.revision!=p.expectedRevision)return "ACCOUNT_CHANGED";
        if(!policy.id.equals(p.policyId))return "POLICY_CHANGED";
        if(now.isBefore(p.terms.createdAt()))return "CLOCK_INVALID";
        if(!now.isBefore(p.terms.expiresAt()))return "EXPIRED";
        if(q==null)return "QUOTE_UNAVAILABLE";
        if(q.instrumentId!=p.instrumentId||!Objects.equals(q.symbol,p.terms.symbol())||!Objects.equals(q.provider,policy.provider))return "QUOTE_IDENTITY_MISMATCH";
        if(q.observedAt==null||q.receivedAt==null||q.pricePaise<=0||q.observedAt.isAfter(q.receivedAt)||q.receivedAt.isAfter(now)
                ||q.observedAt.isBefore(p.terms.createdAt())||Duration.between(q.observedAt,now).compareTo(Duration.ofMillis(policy.limits.maxQuoteAgeMillis()))>0)return "QUOTE_TIME_INVALID";
        try {
            PaperLedgerStore.validate(p.terms,new Quote(q.symbol,q.pricePaise,q.observedAt),new RiskPermit(p.id,p.terms.orderId(),now,true),now,policy.limits);
            if(p.terms.side()==Side.BUY) {
                long needed=reserve(new Order(p.terms,now,Status.OPEN,0,0));
                if(needed>Math.subtractExact(s.cash,s.reserved))return "INSUFFICIENT_CASH";
            } else if(p.terms.side()==Side.SELL && p.terms.quantity()>Math.subtractExact(s.owned,s.reservedShares))return "INSUFFICIENT_SHARES";
        }catch(IllegalArgumentException|ArithmeticException invalid){return "RISK_BLOCKED";}
        return "ACCEPTED_EXECUTION_BLOCKED";
    }
    static void binding(Connection c,long user,long chat,boolean lock)throws SQLException {
        try(var s=statement(c,"SELECT telegram_user_id,telegram_chat_id FROM telegram_binding WHERE binding_key='PRIMARY' AND active=TRUE"+(lock?" FOR SHARE":""));var r=s.executeQuery()) {
            require(r.next()&&r.getLong(1)==user&&r.getLong(2)==chat,"Unauthorized binding");
        }
    }
    private static Pending pending(Connection c,String token,Callback cb,boolean lock)throws SQLException {
        try(var s=statement(c,"SELECT p.payload,p.payload_hash,p.recipient_hash,p.portfolio_id,p.instrument_id,p.expected_revision,t.action,p.decided_token,p.receipt,p.policy_hash FROM paper_approval_token t JOIN paper_approval_proposal p ON p.id=t.proposal_id WHERE t.token_hash=?"+(lock?" FOR UPDATE OF p":""),token);var r=s.executeQuery()) {
            require(r.next(),"Unknown action");String payload=r.getString(1);require(hash(payload).equals(r.getString(2)),"Proposal corruption");
            Proposal p=decode(payload,Proposal.class);require(identity(cb.userId,cb.chatId).equals(r.getString(3))&&p.userId==cb.userId&&p.chatId==cb.chatId,"Wrong recipient");
            require(p.portfolioId==r.getLong(4)&&p.instrumentId==r.getLong(5)&&p.expectedRevision==r.getLong(6),"Proposal columns mismatch");
            return new Pending(p,r.getString(7),r.getString(10),r.getString(8),r.getString(9)==null?null:decode(r.getString(9),Receipt.class));
        }
    }
    private static Snapshot snapshot(Connection c,Proposal p,boolean lock)throws SQLException {
        // Same account lock order as PaperLedgerStore. No full journal replay or unbounded count.
        long legacy;
        try(var s=statement(c,"SELECT current_cash FROM paper_portfolio WHERE id=? AND active=TRUE AND execution_mode='PAPER'"+(lock?" FOR UPDATE":""),p.portfolioId);var r=s.executeQuery()) {require(r.next(),"Account unavailable");legacy=r.getBigDecimal(1).movePointRight(2).longValueExact();}
        long revision,cash,reserved;boolean consistent;
        try(var s=statement(c,"SELECT cash,reserved,revision,opening_cash,last_at,policy,tail FROM paper_ledger_account WHERE portfolio_id=?"+(lock?" FOR UPDATE":""),p.portfolioId);var r=s.executeQuery()) {
            require(r.next(),"Ledger unattached");cash=r.getLong(1);reserved=r.getLong(2);revision=r.getLong(3);
            consistent=cash==legacy&&cash>=0&&reserved>=0&&reserved<=cash;
            if(revision==0)consistent&=cash==r.getLong(4)&&reserved==0&&r.getTimestamp(5)==null&&r.getString(6)==null&&"0".repeat(64).equals(r.getString(7));
            else {try(var h=statement(c,"SELECT receipt,hash,previous_hash,payload FROM paper_ledger_command WHERE portfolio_id=? AND revision=?",p.portfolioId,revision);var row=h.executeQuery()) {
                if(!row.next())consistent=false;else {var head=decode(row.getString(1),PaperLedgerStore.Receipt.class);consistent&=head.revision()==revision&&head.cashPaise()==cash&&head.reservedCashPaise()==reserved&&head.tailHash().equals(r.getString(7))
                        &&head.tailHash().equals(row.getString(2))&&hash(row.getString(3)+"\n"+revision+"\n"+row.getString(4)+"\n"+cash+"\n"+reserved+"\n"+head.orderStatus()).equals(head.tailHash());}
            }}
        }
        long owned=0,shares=0;
        try(var s=statement(c,"SELECT quantity,reserved,hash FROM paper_ledger_position WHERE portfolio_id=? AND instrument_id=?",p.portfolioId,p.instrumentId);var r=s.executeQuery()) {
            if(r.next()){owned=r.getLong(1);shares=r.getLong(2);consistent&=hash(p.portfolioId+":"+p.instrumentId+":"+owned+":"+shares).equals(r.getString(3))&&shares>=0&&owned>=shares;}
        }
        try(var s=statement(c,"SELECT symbol FROM instrument WHERE id=? AND active=TRUE",p.instrumentId);var r=s.executeQuery()){consistent&=r.next()&&r.getString(1).equals(p.terms.symbol());}
        return new Snapshot(revision,cash,reserved,owned,shares,consistent);
    }
    private String newToken(){byte[] bytes=new byte[32];random.nextBytes(bytes);return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);}
    static String identity(long user,long chat){return hash(user+":"+chat);}
    static void begin(Connection c)throws SQLException {c.setAutoCommit(false);c.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);try(var s=c.createStatement()){s.execute("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='10s'; SET LOCAL idle_in_transaction_session_timeout='15s'; SET LOCAL synchronous_commit=on");}}
    private static void rollback(Connection c,Exception e){try{c.rollback();}catch(SQLException x){e.addSuppressed(x);}}
    private static void tokenId(String s){require(s!=null&&s.matches("[A-Za-z0-9_.:-]{1,100}"),"Invalid identifier");}
    private static void require(boolean ok,String message){if(!ok)throw new IllegalArgumentException(message);}
}
