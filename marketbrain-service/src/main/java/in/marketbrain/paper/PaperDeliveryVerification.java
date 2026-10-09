package in.marketbrain.paper;

import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.nio.charset.StandardCharsets;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Disposable PostgreSQL + fake HTTP. Exercises real adapters without internet/provider credentials. */
public final class PaperDeliveryVerification {
    private static final List<Map<String,Object>> checks=new ArrayList<>();
    static final String KEY="NSE_EQ|INE123A01016";
    static final byte[] FIXTURE_KEY=new byte[32];
    static final PolicyVersion POLICY=new PolicyVersion("DELIVERY_FIXTURE","UPSTOX",fixturePolicy(),Duration.ofMinutes(2));
    static Proposal proposal(String id){var base=PaperApprovalVerification.proposal(id,Side.BUY,1,0);return new Proposal(id,1,1,0,111,222,base.terms(),POLICY.id());}
    static void initializeDelivery(String schema)throws Exception{
        PaperApprovalVerification.init(schema);sql(schema,resource("/db/migration/V4__create_upstox_market_data_foundation.sql"));
        sql(schema,resource("/paper/delivery-v1.sql"));
        sql(schema,"UPDATE market_data_source SET enabled=TRUE WHERE code='UPSTOX'; INSERT INTO provider_instrument(source_id,instrument_id,provider_instrument_key,segment,instrument_type) SELECT id,1,'"+KEY+"','NSE_EQ','EQ' FROM market_data_source WHERE code='UPSTOX'");
    }
    static class Fixture {
        final String schema;final PaperApprovalVerification.Time time=new PaperApprovalVerification.Time();
        final AtomicInteger sends=new AtomicInteger(),quotes=new AtomicInteger();final PaperApprovalReview review;final PaperApprovalDelivery delivery;
        Tokens observedTokens;boolean failSend;String quotePayload;
        Fixture()throws Exception{this("paper_verify_"+UUID.randomUUID().toString().replace("-",""),true);}
        Fixture(String schema,boolean initialize)throws Exception{
            this.schema=schema;if(initialize)initializeDelivery(schema);
            quotePayload="{\"status\":\"success\",\"data\":{\"NSE_EQ:FIXTURE\":{\"instrument_token\":\""+KEY+"\",\"symbol\":\"FIXTURE\",\"last_price\":100,\"timestamp\":\""+T+"\",\"last_trade_time\":\""+T.toEpochMilli()+"\"}}}";
            var quote=PaperApprovalHttp.upstox(r->{quotes.incrementAndGet();return new PaperApprovalHttp.Response(200,quotePayload.getBytes(StandardCharsets.UTF_8));},PaperApprovalHttp.jdbcInstrumentKeys(()->connect(schema)),()->"isolated-fixture-not-a-credential",time);
            review=new PaperApprovalReview(()->connect(schema),quote,time,POLICY);
            var send=PaperApprovalHttp.telegram(r->{sends.incrementAndGet();if(failSend)throw new IllegalStateException("Synthetic lost acknowledgement");return new PaperApprovalHttp.Response(200,"{\"ok\":true,\"result\":{\"message_id\":12,\"chat\":{\"id\":222,\"type\":\"private\"}}}".getBytes(StandardCharsets.UTF_8));},()->"123:isolated_fixture_token",time);
            delivery=new PaperApprovalDelivery(()->connect(schema),review,(p,t)->{observedTokens=t;return send.send(p,t);},time,FIXTURE_KEY);
        }
        String action(boolean accept)throws Exception{return new PaperApprovalCallback(review).handle("callback",111,222,"private","mbp:"+(accept?observedTokens.accept():observedTokens.reject()));}
    }
    static void check(String name,Check test){long start=System.nanoTime();var row=new LinkedHashMap<String,Object>();row.put("name",name);try{test.run();row.put("passed",true);}catch(Exception|AssertionError e){row.put("passed",false);row.put("failure",e.getClass().getSimpleName()+": "+e.getMessage());}row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);}
    static void prepare(String restart)throws Exception{
        check("enqueue_commits_proposal_tokens_and_delivery_together",()->{var f=new Fixture();eq(f.delivery.enqueue(proposal("p")),"PENDING");eq(number(f.schema,"SELECT count(*) FROM paper_approval_token"),2L);eq(number(f.schema,"SELECT count(*) FROM paper_approval_delivery"),1L);PaperApprovalVerification.unchanged(f.schema);});
        check("enqueue_replay_keeps_original_tokens",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));eq(f.delivery.enqueue(proposal("p")),"PENDING");eq(number(f.schema,"SELECT count(*) FROM paper_approval_token"),2L);});
        check("conflicting_publication_identity_rejected",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));var p=proposal("p");reject(()->f.delivery.enqueue(new Proposal(p.id(),1,1,1,111,222,p.terms(),p.policyId())));});
        check("outbox_insert_failure_rolls_back_proposal_and_tokens",()->{var f=new Fixture();sql(f.schema,"ALTER TABLE paper_approval_delivery ADD CONSTRAINT fixture_fail CHECK(false)");reject(()->f.delivery.enqueue(proposal("p")));eq(number(f.schema,"SELECT count(*) FROM paper_approval_proposal"),0L);eq(number(f.schema,"SELECT count(*) FROM paper_approval_token"),0L);});
        check("concurrent_enqueue_has_one_durable_publication",()->{var f=new Fixture();var pool=Executors.newFixedThreadPool(2);try{var a=pool.submit(()->f.delivery.enqueue(proposal("p")));var b=pool.submit(()->f.delivery.enqueue(proposal("p")));eq(a.get(20,TimeUnit.SECONDS),b.get(20,TimeUnit.SECONDS));eq(number(f.schema,"SELECT count(*) FROM paper_approval_delivery"),1L);}finally{pool.shutdownNow();}});
        check("revoked_recipient_cannot_enqueue",()->{var f=new Fixture();sql(f.schema,"UPDATE telegram_binding SET active=FALSE");reject(()->f.delivery.enqueue(proposal("p")));eq(number(f.schema,"SELECT count(*) FROM paper_approval_token"),0L);});
        check("acknowledged_delivery_is_not_resent",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));eq(f.delivery.dispatch("p"),"SENT");eq(f.delivery.dispatch("p"),"SENT");eq(f.sends.get(),1);});
        check("concurrent_dispatch_claims_one_send",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));var pool=Executors.newFixedThreadPool(2);try{var a=pool.submit(()->f.delivery.dispatch("p"));var b=pool.submit(()->f.delivery.dispatch("p"));for(var future:List.of(a,b)){if(!Set.of("SENT","SENDING").contains(future.get(20,TimeUnit.SECONDS)))throw new AssertionError("Unexpected state");}eq(f.sends.get(),1);}finally{pool.shutdownNow();}});
        check("expired_delivery_never_sends",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.time.at=T.plusSeconds(120);eq(f.delivery.dispatch("p"),"EXPIRED");eq(f.sends.get(),0);});
        check("revoked_binding_before_dispatch_never_sends",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));sql(f.schema,"UPDATE telegram_binding SET active=FALSE");eq(f.delivery.dispatch("p"),"REVOKED");eq(f.sends.get(),0);});
        check("wrong_key_blocks_without_sending_or_token_reissue",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));byte[] wrong=new byte[32];Arrays.fill(wrong,(byte)1);var other=new PaperApprovalDelivery(()->connect(f.schema),f.review,(p,t)->{throw new AssertionError("Sent");},f.time,wrong);eq(other.dispatch("p"),"KEY_BLOCKED");eq(number(f.schema,"SELECT count(*) FROM paper_approval_token"),2L);});
        check("lost_acknowledgement_is_uncertain_and_not_resent",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.failSend=true;eq(f.delivery.dispatch("p"),"UNCERTAIN");f.failSend=false;eq(f.delivery.dispatch("p"),"UNCERTAIN");eq(f.sends.get(),1);});
        check("sending_after_crash_is_not_automatically_retried",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));sql(f.schema,"UPDATE paper_approval_delivery SET state='SENDING',attempt_id='fixture-crash',attempted_at=now()");eq(f.delivery.dispatch("p"),"SENDING");eq(f.sends.get(),0);});
        check("sent_evidence_and_ciphertext_are_immutable",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));reject(()->sql(f.schema,"UPDATE paper_approval_delivery SET encrypted_tokens='tampered'"));f.delivery.dispatch("p");reject(()->sql(f.schema,"UPDATE paper_approval_delivery SET state='PENDING',attempt_id=NULL,attempted_at=NULL,message_id=NULL"));reject(()->sql(f.schema,"DELETE FROM paper_approval_delivery"));});
        check("delivered_accept_runs_quote_adapter_and_review_only",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");if(!f.action(true).startsWith("PAPER review accepted"))throw new AssertionError("Not accepted");eq(f.quotes.get(),1);PaperApprovalVerification.unchanged(f.schema);});
        check("delivered_reject_makes_no_quote_request",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");if(!f.action(false).contains("rejected"))throw new AssertionError("Not rejected");eq(f.quotes.get(),0);PaperApprovalVerification.unchanged(f.schema);});
        check("wrong_provider_instrument_has_no_fallback",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");f.quotePayload=f.quotePayload.replace(KEY,"NSE_EQ|INE999A01016");if(!f.action(true).contains("QUOTE_UNAVAILABLE"))throw new AssertionError("Quote trusted");});
        check("disabled_provider_mapping_blocks_quote_call",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");sql(f.schema,"UPDATE market_data_source SET enabled=FALSE WHERE code='UPSTOX'");if(!f.action(true).contains("QUOTE_UNAVAILABLE"))throw new AssertionError("Quote trusted");eq(f.quotes.get(),0);});
        check("fresh_snapshot_with_old_trade_is_blocked",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");f.quotePayload=f.quotePayload.replace(Long.toString(T.toEpochMilli()),Long.toString(T.minusSeconds(60).toEpochMilli()));if(!f.action(true).contains("QUOTE_TIME_INVALID"))throw new AssertionError("Old trade trusted");});
        check("callback_retry_after_ack_failure_reuses_receipt",()->{var f=new Fixture();f.delivery.enqueue(proposal("p"));f.delivery.dispatch("p");String first=f.action(true);f.time.at=T.plusSeconds(200);eq(f.action(true),first);eq(f.quotes.get(),1);});
        check("prepare_delivery_restart_fixture",()->{var f=new Fixture(restart,true);f.delivery.enqueue(proposal("pending"));f.delivery.enqueue(proposal("sent"));f.delivery.dispatch("sent");f.action(true);f.delivery.enqueue(proposal("uncertain"));f.failSend=true;f.delivery.dispatch("uncertain");PaperApprovalVerification.unchanged(restart);});
    }
    public static void main(String[] args)throws Exception{
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0])||!args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated phase/schema required");
        long start=System.nanoTime();String schema=args[1];
        if(args[0].equals("--prepare"))prepare(schema);else{
            check("restart_pending_delivery_can_send_once",()->{var f=new Fixture(schema,false);eq(f.delivery.dispatch("pending"),"SENT");eq(f.delivery.dispatch("pending"),"SENT");eq(f.sends.get(),1);});
            check("restart_sent_and_uncertain_are_not_resent",()->{var f=new Fixture(schema,false);eq(f.delivery.dispatch("sent"),"SENT");eq(f.delivery.dispatch("uncertain"),"UNCERTAIN");eq(f.sends.get(),0);});
            check("restart_review_and_account_remain_unchanged",()->{PaperApprovalVerification.unchanged(schema);eq(number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),1L);});
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();var result=new LinkedHashMap<String,Object>();
        result.put("version","PAPER_DELIVERY_REVIEW_V1");result.put("status",failed==0?"ISOLATED_DELIVERY_CHECKS_PASSED":"FAILED");result.put("phase",args[0]);result.put("schema",schema);result.put("checks",checks);result.put("checkCount",checks.size());result.put("failedCount",failed);result.put("elapsedSeconds",(System.nanoTime()-start)/1e9);
        result.put("applicationDatabaseAccessed",false);result.put("actionExecutionEnabled",false);result.put("syntheticDatabaseWritesPerformed",true);result.put("httpTransport","FAKE_NO_NETWORK");result.put("providerCalls",0);result.put("telegramCalls",0);result.put("modelCalls",0);
        if(failed==0){result.put("cashPaise",number(schema,"SELECT cash FROM paper_ledger_account"));result.put("reservedCashPaise",number(schema,"SELECT reserved FROM paper_ledger_account"));result.put("ledgerRevision",number(schema,"SELECT revision FROM paper_ledger_account"));result.put("orderCount",number(schema,"SELECT count(*) FROM paper_ledger_order"));result.put("fillCount",number(schema,"SELECT count(*) FROM paper_ledger_fill"));result.put("decisionCount",number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"));result.put("deliveryCount",number(schema,"SELECT count(*) FROM paper_approval_delivery"));result.put("pendingCount",number(schema,"SELECT count(*) FROM paper_approval_delivery WHERE state='PENDING'"));result.put("uncertainCount",number(schema,"SELECT count(*) FROM paper_approval_delivery WHERE state='UNCERTAIN'"));}
        System.out.println(encode(result));if(failed>0)System.exit(2);
    }
}
