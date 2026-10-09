package in.marketbrain.paper;

import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Fixed synthetic suite on disposable db only. No Telegram, provider, application or model calls. */
public final class PaperApprovalVerification {
    private static final List<Map<String,Object>> checks=new ArrayList<>();
    static final PolicyVersion POLICY=new PolicyVersion("FIXTURE_V1","FIXTURE",fixturePolicy(),Duration.ofMinutes(2));
    static Proposal proposal(String id,Side side,long quantity,long revision) {
        return new Proposal(id,1,1,revision,111,222,new Approval(id,"ORDER-"+id,"FIXTURE",side,quantity,10000,9900,10100,side==Side.HOLD?0:100,T,T.plusSeconds(120)),POLICY.id());
    }
    static MarketQuote quote(){return new MarketQuote(1,"FIXTURE","FIXTURE",10000,T,T);}
    static Callback cb(String token){return new Callback("callback",111,222,true,token);}
    static final class Time extends Clock {
        Instant at=T;public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId zone){return this;}public Instant instant(){return at;}
    }
    static String init(String schema)throws Exception {
        initialize(schema,null);
        sql(schema,resource("/db/migration/V2__make_alert_delivery_channel_neutral.sql"));
        sql(schema,resource("/db/migration/V3__create_telegram_delivery_foundation.sql"));
        sql(schema,resource("/paper/approval-v1.sql"));
        sql(schema,"INSERT INTO telegram_binding(binding_key,telegram_user_id,telegram_chat_id) VALUES('PRIMARY',111,222)");return schema;
    }
    static String freshApproval()throws Exception{return init("paper_verify_"+UUID.randomUUID().toString().replace("-",""));}
    static PaperApprovalReview review(String s,QuoteSource source,Clock time){return new PaperApprovalReview(()->connect(s),source,time,POLICY);}
    static final class Fixture {
        String s;Time time=new Time();AtomicInteger calls=new AtomicInteger();QuoteSource source=p->quote();PaperApprovalReview review;Tokens tokens;
        Fixture()throws Exception{this("p",Side.BUY,10);}
        Fixture(String id,Side side,long qty)throws Exception{s=freshApproval();review=review(s,p->{calls.incrementAndGet();return source.latest(p);},time);tokens=review.issue(proposal(id,side,qty,0));}
        Receipt accept()throws Exception{return review.process(cb(tokens.accept()));}
    }
    static void check(String name,Check test){long start=System.nanoTime();var row=new LinkedHashMap<String,Object>();row.put("name",name);try{test.run();row.put("passed",true);}catch(Exception|AssertionError failure){row.put("passed",false);row.put("failure",failure.getClass().getSimpleName()+": "+failure.getMessage());}row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);}
    static void unchanged(String s)throws Exception{eq(number(s,"SELECT cash FROM paper_ledger_account"),10000000L);eq(number(s,"SELECT reserved FROM paper_ledger_account"),0L);eq(number(s,"SELECT revision FROM paper_ledger_account"),0L);eq(number(s,"SELECT count(*) FROM paper_ledger_order"),0L);eq(number(s,"SELECT count(*) FROM paper_ledger_fill"),0L);}
    static void prepare(String restart)throws Exception {
        check("tokens_are_distinct_and_only_hashes_in_approval_tables",()->{var f=new Fixture();if(f.tokens.accept().equals(f.tokens.reject()))throw new AssertionError("Tokens equal");eq(number(f.s,"SELECT count(*) FROM paper_approval_token WHERE length(token_hash)=64"),2L);
            try(var c=connect(f.s);var s=PaperLedgerStore.statement(c,"SELECT count(*) FROM paper_approval_token WHERE token_hash IN (?,?)",PaperLedgerStore.hash(f.tokens.accept()),PaperLedgerStore.hash(f.tokens.reject()));var rows=s.executeQuery()){rows.next();eq(rows.getLong(1),2L);}unchanged(f.s);});
        check("accept_records_review_without_order_or_reservation",()->{var f=new Fixture();var r=f.accept();eq(r.status(),"ACCEPTED_EXECUTION_BLOCKED");eq(r.actionExecutionEnabled(),false);unchanged(f.s);});
        check("reject_needs_no_quote_and_is_terminal",()->{var f=new Fixture();eq(f.review.process(cb(f.tokens.reject())).status(),"REJECTED");eq(f.calls.get(),0);reject(f::accept);unchanged(f.s);});
        check("unknown_token_never_fetches_quote",()->{var f=new Fixture();reject(()->f.review.process(cb("z".repeat(43))));eq(f.calls.get(),0);});
        check("wrong_user_never_consumes_or_fetches",()->{var f=new Fixture();reject(()->f.review.process(new Callback("x",112,222,true,f.tokens.accept())));eq(f.calls.get(),0);eq(f.accept().status(),"ACCEPTED_EXECUTION_BLOCKED");});
        check("wrong_chat_never_fetches",()->{var f=new Fixture();reject(()->f.review.process(new Callback("x",111,223,true,f.tokens.accept())));eq(f.calls.get(),0);});
        check("nonprivate_callback_never_fetches",()->{var f=new Fixture();reject(()->f.review.process(new Callback("x",111,222,false,f.tokens.accept())));eq(f.calls.get(),0);});
        check("expired_token_is_terminal_without_quote",()->{var f=new Fixture();f.time.at=T.plusSeconds(120);eq(f.accept().status(),"EXPIRED");eq(f.calls.get(),0);});
        check("stale_quote_is_not_retried_into_acceptance",()->{var f=new Fixture();f.time.at=T.plusSeconds(6);eq(f.accept().status(),"QUOTE_TIME_INVALID");f.source=p->new MarketQuote(1,"FIXTURE","FIXTURE",10000,f.time.at,f.time.at);eq(f.accept().status(),"QUOTE_TIME_INVALID");eq(f.calls.get(),1);});
        check("future_quote_is_blocked",()->{var f=new Fixture();f.source=p->new MarketQuote(1,"FIXTURE","FIXTURE",10000,T.plusSeconds(1),T.plusSeconds(1));eq(f.accept().status(),"QUOTE_TIME_INVALID");});
        check("wrong_instrument_quote_is_blocked",()->{var f=new Fixture();f.source=p->new MarketQuote(2,"FIXTURE","FIXTURE",10000,T,T);eq(f.accept().status(),"QUOTE_IDENTITY_MISMATCH");});
        check("wrong_provider_quote_is_blocked",()->{var f=new Fixture();f.source=p->new MarketQuote(1,"FIXTURE","OTHER",10000,T,T);eq(f.accept().status(),"QUOTE_IDENTITY_MISMATCH");});
        check("outside_zone_buy_is_not_chased",()->{var f=new Fixture();f.source=p->new MarketQuote(1,"FIXTURE","FIXTURE",10101,T,T);eq(f.accept().status(),"RISK_BLOCKED");});
        check("insufficient_cash_is_blocked",()->{var f=new Fixture("large",Side.BUY,990);var limits=new Policy(5000,200,10000,20000000,50,100);var custom=new PolicyVersion("FIXTURE_V1","FIXTURE",limits,Duration.ofMinutes(2));var big=proposal("big",Side.BUY,991,0);var r=new PaperApprovalReview(()->connect(f.s),p->quote(),f.time,custom);var tokens=r.issue(big);eq(r.process(cb(tokens.accept())).status(),"INSUFFICIENT_CASH");});
        check("unowned_sell_is_blocked",()->{var f=new Fixture("sell",Side.SELL,1);eq(f.accept().status(),"INSUFFICIENT_SHARES");});
        check("account_change_during_quote_invalidates_acceptance",()->{var f=new Fixture();f.source=p->{store(f.s).execute(1,approve("h",0,"h",Side.HOLD,0));return quote();};eq(f.accept().status(),"ACCOUNT_CHANGED");});
        check("binding_revocation_during_quote_prevents_consumption",()->{var f=new Fixture();f.source=p->{sql(f.s,"UPDATE telegram_binding SET active=FALSE");return quote();};reject(f::accept);eq(number(f.s,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),0L);});
        check("changed_policy_is_blocked",()->{var f=new Fixture();var other=new PolicyVersion("FIXTURE_V2","FIXTURE",fixturePolicy(),Duration.ofMinutes(2));var r=new PaperApprovalReview(()->connect(f.s),p->quote(),f.time,other);eq(r.process(cb(f.tokens.accept())).status(),"POLICY_CHANGED");});
        check("reused_policy_id_with_changed_limits_is_blocked",()->{var f=new Fixture();var other=new PolicyVersion("FIXTURE_V1","FIXTURE",new Policy(4000,200,10000,10000000,50,100),Duration.ofMinutes(2));var r=new PaperApprovalReview(()->connect(f.s),p->quote(),f.time,other);eq(r.process(cb(f.tokens.accept())).status(),"POLICY_CHANGED");});
        check("corrupted_account_projection_prevents_acceptance",()->{var f=new Fixture();sql(f.s,"UPDATE paper_portfolio SET current_cash=current_cash-1");eq(f.accept().status(),"ACCOUNT_INCONSISTENT");eq(number(f.s,"SELECT count(*) FROM paper_ledger_order"),0L);});
        check("duplicate_after_expiry_returns_original_receipt",()->{var f=new Fixture();var first=f.accept();f.time.at=T.plusSeconds(999);eq(f.accept(),first);eq(f.calls.get(),1);});
        check("opposite_action_cannot_reverse_decision",()->{var f=new Fixture();f.accept();reject(()->f.review.process(cb(f.tokens.reject())));eq(number(f.s,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),1L);});
        check("concurrent_duplicate_records_one_receipt",()->{var f=new Fixture();var pool=Executors.newFixedThreadPool(2);try{var a=pool.submit(f::accept);var b=pool.submit(f::accept);eq(a.get(20,TimeUnit.SECONDS),b.get(20,TimeUnit.SECONDS));eq(number(f.s,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),1L);unchanged(f.s);}finally{pool.shutdownNow();}});
        check("callback_id_conflict_rolls_back_second_decision",()->{var f=new Fixture();f.accept();var second=f.review.issue(proposal("second",Side.BUY,1,0));reject(()->f.review.process(cb(second.accept())));eq(number(f.s,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),1L);});
        check("proposal_and_receipt_are_immutable",()->{var f=new Fixture();reject(()->sql(f.s,"UPDATE paper_approval_proposal SET payload='{}'"));f.accept();reject(()->sql(f.s,"UPDATE paper_approval_proposal SET receipt='{}'"));reject(()->sql(f.s,"DELETE FROM paper_approval_token"));});
        check("hold_cannot_issue_action_tokens",()->{String s=freshApproval();reject(()->review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).issue(proposal("hold",Side.HOLD,0,0)));eq(number(s,"SELECT count(*) FROM paper_approval_token"),0L);});
        check("missing_ledger_never_reseeds",()->{String s=freshApproval();sql(s,"DELETE FROM paper_ledger_account");reject(()->review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).issue(proposal("missing",Side.BUY,1,0)));eq(number(s,"SELECT count(*) FROM paper_ledger_account"),0L);});
        check("quote_failure_is_recorded_without_retry",()->{var f=new Fixture();f.source=p->{throw new IllegalStateException("fixture failure");};eq(f.accept().status(),"QUOTE_UNAVAILABLE");eq(f.accept().status(),"QUOTE_UNAVAILABLE");eq(f.calls.get(),1);});
        check("expiry_while_fetching_quote_is_rechecked",()->{var f=new Fixture();f.source=p->{f.time.at=T.plusSeconds(120);return quote();};eq(f.accept().status(),"EXPIRED");});
        check("prepare_restart_receipt",()->{init(restart);var r=review(restart,p->quote(),Clock.fixed(T,ZoneOffset.UTC));var t=r.issue(proposal("restart",Side.BUY,1,0));r.process(cb(t.accept()));
            // Disposable test helper only. This synthetic token is not a production credential or an output artifact.
            sql(restart,"CREATE TABLE fixture_recovery_token(value TEXT); INSERT INTO fixture_recovery_token VALUES ('"+t.accept()+"')");unchanged(restart);});
    }
    public static void main(String[] args)throws Exception {
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0])||!args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated phase/schema required");
        long start=System.nanoTime();String schema=args[1];
        if(args[0].equals("--prepare"))prepare(schema);else {
            check("restart_duplicate_returns_saved_receipt_without_quote",()->{String token;try(var c=connect(schema);var s=c.createStatement();var r=s.executeQuery("SELECT value FROM fixture_recovery_token")){r.next();token=r.getString(1);}var review=review(schema,p->{throw new AssertionError("Quote called on replay");},Clock.fixed(T.plusSeconds(999),ZoneOffset.UTC));eq(review.process(cb(token)).status(),"ACCEPTED_EXECUTION_BLOCKED");});
            check("restart_preserves_account_and_no_orders",()->unchanged(schema));
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();
        var result=new LinkedHashMap<String,Object>();result.put("version",PaperApprovalReview.VERSION);result.put("phase",args[0]);result.put("schema",schema);result.put("status",failed==0?"ISOLATED_APPROVAL_CHECKS_PASSED":"FAILED");result.put("checks",checks);result.put("checkCount",checks.size());result.put("failedCount",failed);result.put("elapsedSeconds",(System.nanoTime()-start)/1e9);result.put("applicationDatabaseAccessed",false);result.put("actionExecutionEnabled",false);result.put("syntheticDatabaseWritesPerformed",true);result.put("providerCalls",0);result.put("telegramCalls",0);result.put("modelCalls",0);
        if(failed==0){result.put("cashPaise",number(schema,"SELECT cash FROM paper_ledger_account"));result.put("reservedCashPaise",number(schema,"SELECT reserved FROM paper_ledger_account"));result.put("ledgerRevision",number(schema,"SELECT revision FROM paper_ledger_account"));result.put("orderCount",number(schema,"SELECT count(*) FROM paper_ledger_order"));result.put("fillCount",number(schema,"SELECT count(*) FROM paper_ledger_fill"));result.put("decisionCount",number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"));}
        System.out.println(encode(result));if(failed>0)System.exit(2);
    }
}
