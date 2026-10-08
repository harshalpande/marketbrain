package in.marketbrain.paper;

import java.sql.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.*;

/** Fixed fixtures against an isolated Docker-only database address. Never loads Spring or environment secrets. */
public final class PaperPersistenceVerification {
    private static final Connections DB = () -> DriverManager.getConnection(
            "jdbc:postgresql://db:5432/paper_fixture?connectTimeout=5&socketTimeout=20",
            "paper_fixture", "isolated_fixture_only");
    private static final List<Map<String,Object>> CHECKS = new ArrayList<>();
    @FunctionalInterface private interface Check { void run() throws Exception; }
    private static void check(String name, Check body) {
        long start = System.nanoTime(); Map<String,Object> r = new LinkedHashMap<>(); r.put("name", name);
        try { body.run(); r.put("passed", true); r.put("failure", null); }
        catch (Exception | AssertionError e) { r.put("passed", false); r.put("failure", e.getClass().getSimpleName() + ": " + e.getMessage()); }
        r.put("elapsedMillis", (System.nanoTime()-start)/1_000_000.0); CHECKS.add(r);
    }
    static Command approve(String id, Approval a) { return new Command(id,T,Kind.APPROVE,a,null,quote(10000),permit(a),null); }
    static Command fill(String id, String fillId, String order, long quantity, long fee) {
        return new Command(id,T,Kind.FILL,null,new Fill(fillId,order,quantity,10000,fee),quote(10000),new RiskPermit("APP-"+order,order,T,true),null);
    }
    static Command cancel(String id, String order) { return new Command(id,T,Kind.CANCEL,null,null,null,null,order); }
    private static PaperPersistenceEngineering fresh() throws SQLException {
        var p = repo("paper_verify_"+UUID.randomUUID().toString().replace("-","")); p.initialize(); return p;
    }
    private static PaperPersistenceEngineering repo(String schema) { return new PaperPersistenceEngineering(DB,schema,fixturePolicy()); }
    private static void eq(Object actual, Object expected) { if(!Objects.equals(actual,expected)) throw new AssertionError(actual+" != "+expected); }
    private static void reject(Check action) throws Exception {
        try { action.run(); } catch (SQLException | IllegalArgumentException e) { return; }
        throw new AssertionError("Expected fail-closed rejection");
    }
    private static void executeSql(String sql) throws SQLException { try(var c=DB.open();var s=c.createStatement()){s.execute(sql);} }
    private static void prepareChecks() {
        check("committed_approval_reopens_with_reservation", () -> {var p=fresh();p.execute(approve("a",proposal("buy",Side.BUY,10))); eq(p.inspect().audit().account().reservedCashPaise(),101100L);});
        check("same_command_duplicate_no_revision_or_cash_change", () -> {var p=fresh();var a=approve("a",proposal("buy",Side.BUY,10));p.execute(a);var r=p.execute(a);eq(r.duplicate(),true);eq(r.revision(),1L);});
        check("conflicting_id_rejected_without_write", () -> {var p=fresh();p.execute(approve("a",proposal("buy",Side.BUY,10)));reject(()->p.execute(approve("a",proposal("buy",Side.BUY,11))));eq(p.inspect().revision(),1L);});
        check("partial_fill_and_cancel_survive_reconstruction", () -> {var p=fresh();p.execute(approve("a",proposal("buy",Side.BUY,10)));p.execute(fill("f","fill1","buy",4,10));p.execute(cancel("c","buy"));var r=p.inspect();eq(r.audit().account().cashPaise(),9959990L);eq(r.audit().account().reservedCashPaise(),0L);eq(r.audit().account().holdings().get("FIXTURE"),4L);});
        check("duplicate_fill_different_command_does_not_debit", () -> {var p=fresh();p.execute(approve("a",proposal("buy",Side.BUY,10)));p.execute(fill("f","f1","buy",4,10));p.execute(fill("retry","f1","buy",4,10));eq(p.inspect().audit().account().fillCount(),1);eq(p.inspect().audit().account().cashPaise(),9959990L);});
        check("overfill_rolls_back_without_journal_append", () -> {var p=fresh();p.execute(approve("a",proposal("buy",Side.BUY,10)));reject(()->p.execute(fill("f","f1","buy",11,0)));eq(p.inspect().revision(),1L);eq(p.inspect().audit().account().cashPaise(),10000000L);});
        check("transaction_failure_rolls_back_insert_and_projection", () -> {
            String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();
            var failing=new PaperPersistenceEngineering(DB,s,fixturePolicy(),c->{throw new SQLException("Injected before-commit failure");});
            reject(()->failing.execute(approve("a",proposal("buy",Side.BUY,10))));eq(p.inspect().revision(),0L);
        });
        check("lost_commit_ack_retry_reconciles_once", () -> {
            String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();var a=approve("a",proposal("buy",Side.BUY,10));
            var failing=new PaperPersistenceEngineering(DB,s,fixturePolicy(),c->{c.commit();throw new SQLException("Simulated lost acknowledgement after real commit");});
            reject(()->failing.execute(a));eq(p.execute(a).duplicate(),true);eq(p.inspect().revision(),1L);
        });
        check("terminated_backend_rolls_back_uncommitted_command", () -> {
            String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();
            var failing=new PaperPersistenceEngineering(DB,s,fixturePolicy(),c->{int pid;try(var q=c.createStatement();var r=q.executeQuery("SELECT pg_backend_pid()")){r.next();pid=r.getInt(1);}executeSql("SELECT pg_terminate_backend("+pid+")");throw new SQLException("Backend terminated before commit");});
            reject(()->failing.execute(approve("a",proposal("buy",Side.BUY,10))));eq(p.inspect().revision(),0L);
        });
        check("concurrent_approvals_cannot_double_spend", () -> {
            var p=fresh();var start=new CountDownLatch(1);var pool=Executors.newFixedThreadPool(2);
            try { List<Future<Boolean>> results=new ArrayList<>();for(String id:List.of("one","two")){results.add(pool.submit(()->{start.await();try{p.execute(approve(id,proposal(id,Side.BUY,600)));return true;}catch(IllegalArgumentException e){return false;}}));}
                start.countDown();int accepted=0;for(var f:results)if(f.get(15,TimeUnit.SECONDS))accepted++;eq(accepted,1);eq(p.inspect().revision(),1L);
            } finally {pool.shutdownNow();}
        });
        check("concurrent_same_id_has_one_commit", () -> {
            var p=fresh();var a=approve("a",proposal("buy",Side.BUY,10));var pool=Executors.newFixedThreadPool(2);
            try {var one=pool.submit(()->p.execute(a));var two=pool.submit(()->p.execute(a));var x=one.get(15,TimeUnit.SECONDS);var y=two.get(15,TimeUnit.SECONDS);eq(x.duplicate()!=y.duplicate(),true);eq(p.inspect().revision(),1L);}finally{pool.shutdownNow();}
        });
        check("lock_timeout_fails_without_partial_write", () -> {
            String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();
            try(var c=DB.open()){c.setAutoCommit(false);try(var q=c.createStatement()){q.execute("SELECT id FROM "+s+".account WHERE id=1 FOR UPDATE");}
                try{p.execute(approve("a",proposal("buy",Side.BUY,10)));throw new AssertionError("Lock should time out");}catch(SQLException e){eq(e.getSQLState(),"55P03");}finally{c.rollback();}}
            eq(p.inspect().revision(),0L);
        });
        check("tampered_projection_blocks_reopen", () -> {String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();executeSql("UPDATE "+s+".account SET audit='{}'");reject(p::inspect);});
        check("tampered_command_hash_blocks_reopen", () -> {String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();p.execute(approve("a",proposal("buy",Side.BUY,10)));executeSql("UPDATE "+s+".command SET hash='"+"0".repeat(64)+"'");reject(p::inspect);});
        check("missing_account_never_reseeds", () -> {String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();executeSql("DELETE FROM "+s+".account");reject(p::inspect);});
        check("changed_policy_blocks_replay", () -> {String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");var p=repo(s);p.initialize();reject(()->new PaperPersistenceEngineering(DB,s,new Policy(4000,200,10000,10000000,50,100)).inspect());});
        check("no_op_time_cannot_hide_clock_rollback", () -> {var p=fresh();p.execute(new Command("expiry",T.plusSeconds(1),Kind.EXPIRE,null,null,null,null,null));reject(()->p.execute(approve("a",proposal("buy",Side.BUY,10))));eq(p.inspect().revision(),1L);});
        check("capacity_stops_without_evicting_ids", () -> {var p=fresh();for(int i=0;i<MAX_COMMANDS;i++)p.execute(new Command("expire"+i,T,Kind.EXPIRE,null,null,null,null,null));reject(()->p.execute(new Command("extra",T,Kind.EXPIRE,null,null,null,null,null)));eq(p.inspect().revision(),(long)MAX_COMMANDS);eq(p.execute(new Command("expire0",T,Kind.EXPIRE,null,null,null,null,null)).duplicate(),true);});
        check("hold_persists_without_an_order", () -> {var p=fresh();p.execute(approve("hold",proposal("hold",Side.HOLD,0)));eq(p.inspect().audit().account().orders().size(),0);eq(p.inspect().audit().account().approvalCount(),1);});
        check("unowned_sell_rejected", () -> {var p=fresh();reject(()->p.execute(approve("sell",proposal("sell",Side.SELL,1))));eq(p.inspect().revision(),0L);});
    }
    private static void seedRestart(String schema) throws SQLException {
        var p=repo(schema);p.initialize();p.execute(approve("a-buy",proposal("buy",Side.BUY,10)));
        p.execute(fill("f-buy1","buy1","buy",4,10));p.execute(fill("f-buy2","buy2","buy",6,10));
        p.execute(approve("a-sell",proposal("sell",Side.SELL,4)));p.execute(fill("f-sell","sell1","sell",2,10));
        p.execute(cancel("c-sell","sell"));p.execute(approve("a-pending",proposal("pending",Side.BUY,2)));
    }
    public static void main(String[] args) throws Exception {
        if(args.length!=2 || !Set.of("--prepare","--recover").contains(args[0]) || !args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Fixed isolated fixture phase and schema required");
        long start=System.nanoTime();String phase=args[0];String schema=args[1];String server;
        try(var c=DB.open();var s=c.createStatement();var r=s.executeQuery("SELECT version()")){r.next();server=r.getString(1);}
        if(phase.equals("--prepare")){
            prepareChecks();check("prepare_restart_fixture",()->seedRestart(schema));
        }else{
            check("fresh_jvm_after_database_restart_reconciles",()->{var r=repo(schema).inspect();eq(r.revision(),7L);eq(r.audit().account().cashPaise(),9919970L);eq(r.audit().account().reservedCashPaise(),20300L);eq(r.audit().account().holdings().get("FIXTURE"),8L);});
            check("post_restart_duplicate_fill_has_no_effect",()->{var r=repo(schema).execute(fill("f-buy1","buy1","buy",4,10));eq(r.duplicate(),true);eq(r.revision(),7L);eq(r.audit().account().cashPaise(),9919970L);});
            check("post_restart_expiry_releases_only_remaining_reservation",()->{var p=repo(schema);p.execute(new Command("expire-after-restart",T.plusSeconds(120),Kind.EXPIRE,null,null,null,null,null));var r=p.inspect();eq(r.revision(),8L);eq(r.audit().account().reservedCashPaise(),0L);eq(r.audit().account().cashPaise(),9919970L);eq(r.audit().account().holdings().get("FIXTURE"),8L);eq(r.audit().account().orders().get("pending").status(),Status.EXPIRED);});
        }
        Map<String,Object> result=new LinkedHashMap<>();long failed=CHECKS.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();
        result.put("version",PaperPersistenceEngineering.VERSION);result.put("phase",phase);result.put("status",failed==0?"ISOLATED_DATABASE_CHECKS_PASSED":"FAILED");result.put("checks",CHECKS);result.put("checkCount",CHECKS.size());result.put("failedCount",failed);result.put("databaseVersion",server);result.put("schema",schema);
        result.put("elapsedSeconds",(System.nanoTime()-start)/1_000_000_000.0);result.put("syntheticDatabaseWritesPerformed",true);result.put("applicationDatabaseAccessed",false);result.put("runtimePaperAccountEnabled",false);result.put("providerCallCount",0);result.put("modelCallCount",0);result.put("realOrdersCreated",0);result.put("actionExecutionEnabled",false);
        if(failed==0)result.put("receipt",repo(schema).inspect());
        System.out.println(encode(result));if(failed!=0)System.exit(2);
    }
}
