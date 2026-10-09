package in.marketbrain.paper;

import java.util.*;
import java.util.concurrent.*;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Disposable database only; V28 + key-binding checks. No application or external clients. */
public final class PaperStorageVerification {
    static final byte[] KEY=new byte[32];static{Arrays.fill(KEY,(byte)7);}
    private static final List<Map<String,Object>> checks=new ArrayList<>();
    static void init(String schema)throws Exception{
        initialize(schema,null);
        sql(schema,resource("/db/migration/V2__make_alert_delivery_channel_neutral.sql"));
        sql(schema,resource("/db/migration/V3__create_telegram_delivery_foundation.sql"));
        sql(schema,resource("/db/migration/V28__attach_paper_approval_storage.sql"));
    }
    static String fixture()throws Exception{String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");init(s);return s;}
    static void bind(String s)throws Exception{PaperApprovalStorage.bind(()->connect(s),KEY);}
    static void check(String name,Check work){long start=System.nanoTime();var row=new LinkedHashMap<String,Object>();row.put("name",name);try{work.run();row.put("passed",true);}catch(Exception|AssertionError failure){row.put("passed",false);row.put("failure",failure.getClass().getSimpleName());}row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);}
    public static void main(String[] args)throws Exception{
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0])||!args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated phase/schema required");
        long start=System.nanoTime();String restart=args[1];
        if(args[0].equals("--prepare")){
            check("migration_preserves_account_and_empty_approvals",()->{String s=fixture();PaperApprovalVerification.unchanged(s);eq(number(s,"SELECT count(*) FROM paper_approval_delivery"),0L);eq(number(s,"SELECT count(*) FROM paper_approval_token"),0L);});
            check("first_key_binding_verifies_encrypted_probe",()->{String s=fixture();bind(s);PaperApprovalStorage.verify(()->connect(s),KEY);eq(number(s,"SELECT count(*) FROM paper_approval_key_binding"),1L);});
            check("same_key_replay_preserves_binding",()->{String s=fixture();bind(s);sql(s,"CREATE TABLE fixture_before AS SELECT * FROM paper_approval_key_binding");bind(s);eq(number(s,"SELECT count(*) FROM (SELECT * FROM paper_approval_key_binding EXCEPT SELECT * FROM fixture_before) q"),0L);});
            check("wrong_key_does_not_replace_binding",()->{String s=fixture();bind(s);byte[] other=new byte[32];Arrays.fill(other,(byte)9);reject(()->PaperApprovalStorage.bind(()->connect(s),other));PaperApprovalStorage.verify(()->connect(s),KEY);});
            check("missing_binding_is_not_created_by_read",()->{String s=fixture();reject(()->PaperApprovalStorage.verify(()->connect(s),KEY));eq(number(s,"SELECT count(*) FROM paper_approval_key_binding"),0L);});
            check("concurrent_setup_keeps_single_binding",()->{String s=fixture();var pool=Executors.newFixedThreadPool(2);try{var a=pool.submit(()->{bind(s);return true;});var b=pool.submit(()->{bind(s);return true;});eq(a.get(20,TimeUnit.SECONDS),true);eq(b.get(20,TimeUnit.SECONDS),true);eq(number(s,"SELECT count(*) FROM paper_approval_key_binding"),1L);}finally{pool.shutdownNow();}});
            check("unbound_existing_proposals_block_setup",()->{String s=fixture();sql(s,"INSERT INTO paper_approval_proposal(id,portfolio_id,instrument_id,recipient_hash,expected_revision,payload,payload_hash,policy_hash) VALUES('orphan',1,1,repeat('a',64),0,'{}',repeat('a',64),repeat('a',64))");reject(()->bind(s));eq(number(s,"SELECT count(*) FROM paper_approval_key_binding"),0L);});
            check("key_binding_cannot_be_updated_or_deleted",()->{String s=fixture();bind(s);reject(()->sql(s,"UPDATE paper_approval_key_binding SET fingerprint=repeat('b',64)"));reject(()->sql(s,"DELETE FROM paper_approval_key_binding"));});
            check("failed_binding_insert_rolls_back",()->{String s=fixture();sql(s,"ALTER TABLE paper_approval_key_binding ADD CONSTRAINT fixture_failure CHECK(false)");reject(()->bind(s));eq(number(s,"SELECT count(*) FROM paper_approval_key_binding"),0L);});
            check("prepare_storage_restart_fixture",()->{init(restart);bind(restart);PaperApprovalVerification.unchanged(restart);});
        }else{
            check("restart_accepts_original_key_without_rebinding",()->{bind(restart);PaperApprovalStorage.verify(()->connect(restart),KEY);eq(number(restart,"SELECT count(*) FROM paper_approval_key_binding"),1L);});
            check("restart_retains_account_and_no_approval_activity",()->{PaperApprovalVerification.unchanged(restart);eq(number(restart,"SELECT count(*) FROM paper_approval_proposal"),0L);eq(number(restart,"SELECT count(*) FROM paper_approval_token"),0L);eq(number(restart,"SELECT count(*) FROM paper_approval_delivery"),0L);});
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();var r=new LinkedHashMap<String,Object>();
        r.put("version","PAPER_STORAGE_REVIEW_V1");r.put("status",failed==0?"ISOLATED_STORAGE_CHECKS_PASSED":"FAILED");r.put("phase",args[0]);r.put("schema",restart);r.put("checks",checks);r.put("checkCount",checks.size());r.put("failedCount",failed);r.put("elapsedSeconds",(System.nanoTime()-start)/1e9);
        r.put("applicationDatabaseAccessed",false);r.put("actionExecutionEnabled",false);r.put("syntheticDatabaseWritesPerformed",true);r.put("providerCalls",0);r.put("telegramCalls",0);r.put("modelCalls",0);
        if(failed==0){r.put("cashPaise",number(restart,"SELECT cash FROM paper_ledger_account"));r.put("reservedCashPaise",number(restart,"SELECT reserved FROM paper_ledger_account"));r.put("ledgerRevision",number(restart,"SELECT revision FROM paper_ledger_account"));r.put("orderCount",number(restart,"SELECT count(*) FROM paper_ledger_order"));r.put("fillCount",number(restart,"SELECT count(*) FROM paper_ledger_fill"));r.put("bindingCount",number(restart,"SELECT count(*) FROM paper_approval_key_binding"));r.put("proposalCount",number(restart,"SELECT count(*) FROM paper_approval_proposal"));r.put("deliveryCount",number(restart,"SELECT count(*) FROM paper_approval_delivery"));}
        System.out.println(encode(r));if(failed>0)System.exit(2);
    }
}
