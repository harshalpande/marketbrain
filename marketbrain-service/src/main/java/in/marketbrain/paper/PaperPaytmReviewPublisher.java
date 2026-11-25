package in.marketbrain.paper;

import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import java.sql.*;
import java.time.*;
import java.util.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperLedgerStore.*;

/** Bounded internal test publisher. No HTTP endpoint, scheduler or automatic activation. */
public final class PaperPaytmReviewPublisher {
    public static final String ROLE="marketbrain-paper-publisher";
    private static final List<String> CASES=List.of("ACCEPT","REJECT","EXPIRE");
    public record Plan(String batchId, List<Proposal> proposals, Map<String,Object> identity) {
        public Plan { proposals=List.copyOf(proposals);identity=Map.copyOf(identity); }
    }
    private final Connections connections;
    private final PaytmPaperReviewAdapter quotes;
    private final PaperApprovalDelivery delivery;
    private final Clock clock;

    public static PaperPaytmReviewPublisher create(Connections publisherConnections, PaytmPaperReviewAdapter quotes,
            PaperApprovalDelivery.Sender sender, byte[] existingBoundKey)throws Exception {
        Connections guarded=()->{
            var c=publisherConnections.open();
            try { verifyRole(c);return c; } catch(Exception failure){c.close();throw failure;}
        };
        PaperApprovalStorage.verify(guarded,existingBoundKey); // Never bind or replace the key here.
        var review=new PaperApprovalReview(guarded,quotes,quotes.clock(),PaperReviewTestPolicy.paytmPolicy());
        return new PaperPaytmReviewPublisher(guarded,quotes,new PaperApprovalDelivery(guarded,review,sender,quotes.clock(),existingBoundKey));
    }
    PaperPaytmReviewPublisher(Connections connections,PaytmPaperReviewAdapter quotes,PaperApprovalDelivery delivery) {
        this.connections=Objects.requireNonNull(connections);this.quotes=Objects.requireNonNull(quotes);
        this.delivery=Objects.requireNonNull(delivery);this.clock=quotes.clock();
    }
    static void verifyRole(Connection c)throws SQLException {
        try(var s=c.prepareStatement("SELECT current_user,session_user,rolsuper,rolcreaterole,rolcreatedb,rolreplication,rolbypassrls, "
                +"pg_has_role(current_user,(SELECT relowner FROM pg_class WHERE oid='paper_approval_proposal'::regclass),'MEMBER') "
                +"FROM pg_roles WHERE rolname=current_user")) {
            s.setQueryTimeout(10);
            try(var r=s.executeQuery()) {
                if(!r.next()||!ROLE.equals(r.getString(1))||!ROLE.equals(r.getString(2)))throw new SQLException("PUBLISHER_ROLE_REQUIRED");
                for(int i=3;i<=8;i++)if(r.getBoolean(i)||r.wasNull())throw new SQLException("PUBLISHER_ROLE_TOO_PRIVILEGED");
            }
        }
    }
    /** One real reference read for three test proposals; recipient/revision come from stored state. */
    public Plan prepare(String batchId,long portfolioId,String symbol)throws SQLException {
        if(batchId==null||!batchId.matches("[a-f0-9]{32}")||portfolioId<=0)throw new IllegalArgumentException("Invalid batch identity");
        var reference=quotes.reference(symbol);var q=reference.quote();Instant now=clock.instant();
        requireReference(q,symbol,now);
        long low=Math.max(1,Math.floorDiv(Math.multiplyExact(q.pricePaise(),9950),10000));
        long high=Math.floorDiv(Math.multiplyExact(q.pricePaise(),10050),10000);
        // Keep the whole permitted zone inside the approved maximum notional.
        high=Math.min(high,PaperReviewTestPolicy.paytmPolicy().limits().maxOrderNotionalPaise());
        try(var c=connections.open()) {
            begin(c);
            try {
                long user,chat;
                try(var s=statement(c,"SELECT telegram_user_id,telegram_chat_id FROM telegram_binding WHERE binding_key='PRIMARY' AND active=TRUE FOR SHARE");var r=s.executeQuery()) {
                    if(!r.next())throw new IllegalStateException("ACTIVE_PRIVATE_BINDING_REQUIRED");
                    user=r.getLong(1);chat=r.getLong(2);
                }
                long revision;
                try(var s=statement(c,"SELECT revision FROM paper_ledger_account WHERE portfolio_id=?",portfolioId);var r=s.executeQuery()) {
                    if(!r.next())throw new IllegalStateException("ATTACHED_LEDGER_REQUIRED");revision=r.getLong(1);
                }
                var proposals=new ArrayList<Proposal>();
                for(String test:CASES) {
                    String id="PAYTM_TEST_"+batchId+"_"+test;
                    var terms=new Approval(id,id,symbol,Side.BUY,1,q.pricePaise(),low,high,0,now,now.plusSeconds(100));
                    var p=new Proposal(id,portfolioId,q.instrumentId(),revision,user,chat,terms,PaperReviewTestPolicy.paytmPolicy().id());
                    var account=snapshot(c,p,true);
                    if(!account.consistent()||account.revision()!=revision||account.cash()-account.reserved()<high)
                        throw new IllegalStateException("ACCOUNT_NOT_READY_FOR_REVIEW");
                    proposals.add(p);
                }
                requireReference(q,symbol,clock.instant());c.commit();
                return new Plan(batchId,proposals,reference.identity());
            }catch(Exception failure){c.rollback();throw failure;}
        }
    }
    /** Persist this exact immutable plan before dispatch; never reprice on retry. All three enqueue atomically. */
    public List<String> enqueue(Plan plan)throws SQLException {validate(plan);return delivery.enqueueBatch(plan.proposals());}
    /** One explicit dispatch only. Existing durable state prevents uncertain or completed sends being repeated. */
    public String dispatch(Plan plan,String test)throws SQLException {
        validate(plan);int i=CASES.indexOf(test);if(i<0)throw new IllegalArgumentException("Unknown review case");
        return delivery.dispatch(plan.proposals().get(i).id());
    }
    private void validate(Plan plan) {
        if(plan==null||plan.batchId()==null||!plan.batchId().matches("[a-f0-9]{32}")||plan.proposals().size()!=3)
            throw new IllegalArgumentException("Invalid review plan");
        var first=plan.proposals().getFirst();
        for(int i=0;i<3;i++) {
            var p=plan.proposals().get(i);var a=p.terms();
            if(!p.id().equals("PAYTM_TEST_"+plan.batchId()+"_"+CASES.get(i))||!p.policyId().equals(PaperReviewTestPolicy.paytmPolicy().id())
                ||p.portfolioId()!=first.portfolioId()||p.instrumentId()!=first.instrumentId()||p.expectedRevision()!=first.expectedRevision()
                ||p.userId()!=first.userId()||p.chatId()!=first.chatId()||!a.symbol().equals(first.terms().symbol())
                ||a.side()!=Side.BUY||a.quantity()!=1||a.feeBudgetPaise()!=0||!a.orderId().equals(p.id())
                ||a.referencePaise()!=first.terms().referencePaise()||a.referencePaise()>500000||a.zoneMaxPaise()>500000
                ||a.zoneMinPaise()!=first.terms().zoneMinPaise()||a.zoneMaxPaise()!=first.terms().zoneMaxPaise()
                ||!a.createdAt().equals(first.terms().createdAt())||!a.expiresAt().equals(a.createdAt().plusSeconds(100)))
                throw new IllegalArgumentException("Review plan changed");
        }
    }
    private static void requireReference(MarketQuote q,String symbol,Instant now) {
        if(q==null||q.instrumentId()<=0||!Objects.equals(q.symbol(),symbol)||!"PAYTM".equals(q.provider())
            ||q.pricePaise()<=0||q.pricePaise()>500000||q.observedAt()==null||q.receivedAt()==null
            ||q.observedAt().isAfter(q.receivedAt())||q.receivedAt().isAfter(now)
            ||Duration.between(q.observedAt(),now).compareTo(Duration.ofSeconds(15))>0)
            throw new IllegalArgumentException("Fresh bounded Paytm reference required");
    }
}
