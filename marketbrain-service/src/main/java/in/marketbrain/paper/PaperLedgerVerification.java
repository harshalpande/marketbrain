package in.marketbrain.paper;

import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperLedgerStore.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Only the disposable Docker db alias; no application credentials/configuration accepted. */
public final class PaperLedgerVerification {
    private static final List<Map<String,Object>> checks=new ArrayList<>();
    @FunctionalInterface interface Check {void run() throws Exception;}
    static Connection connect(String schema)throws SQLException {
        Connection c=DriverManager.getConnection("jdbc:postgresql://db:5432/paper_fixture?connectTimeout=5&socketTimeout=20","paper_fixture","isolated_fixture_only");
        c.setSchema(schema);return c;
    }
    static String resource(String name)throws Exception {try(var stream=PaperLedgerVerification.class.getResourceAsStream(name)){return new String(Objects.requireNonNull(stream).readAllBytes(),StandardCharsets.UTF_8);}}
    static void initialize(String schema,String alteration)throws Exception {
        if(!schema.matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated schema required");
        try(var c=connect("public")) {
            c.setAutoCommit(false);
            try(var s=c.createStatement()) {
                s.execute("CREATE SCHEMA "+schema);c.setSchema(schema);
                s.execute(resource("/db/migration/V1__create_marketbrain_paper_foundation.sql"));
                s.execute("INSERT INTO instrument(exchange,symbol,display_name) VALUES ('NSE','FIXTURE','Synthetic only')");
                if(alteration!=null)s.execute(alteration);
                s.execute(resource("/paper/ledger-v1.sql"));c.commit();
            }catch(Exception e){c.rollback();throw e;}
        }
    }
    static String fresh()throws Exception {return fresh(null);}
    static String fresh(String alteration)throws Exception {String s="paper_verify_"+UUID.randomUUID().toString().replace("-","");initialize(s,alteration);return s;}
    static PaperLedgerStore store(String schema){return new PaperLedgerStore(()->connect(schema),fixturePolicy());}
    static Command approve(String id,long revision,String order,Side side,long qty){var a=proposal(order,side,qty);return new Command(id,revision,T,Kind.APPROVE,1,a,null,quote(10000),permit(a),null);}
    static Command fill(String id,long revision,String order,String fill,long qty,long fee){return new Command(id,revision,T,Kind.FILL,0,null,new Fill(fill,order,qty,10000,fee),quote(10000),new RiskPermit("APP-"+order,order,T,true),null);}
    static Command terminal(String id,long revision,String order,boolean expire){return new Command(id,revision,expire?T.plusSeconds(120):T,expire?Kind.EXPIRE:Kind.CANCEL,0,null,null,null,null,order);}
    static long number(String schema,String sql)throws SQLException {try(var c=connect(schema);var s=c.createStatement();var r=s.executeQuery(sql)){r.next();return r.getLong(1);}}
    static void sql(String schema,String sql)throws SQLException {try(var c=connect(schema);var s=c.createStatement()){s.execute(sql);}}
    static void eq(Object a,Object b){if(!Objects.equals(a,b))throw new AssertionError(a+" != "+b);}
    static void reject(Check body)throws Exception {try{body.run();}catch(SQLException|IllegalArgumentException|ArithmeticException expected){return;}throw new AssertionError("Expected rejection");}
    static void check(String name,Check body){long start=System.nanoTime();Map<String,Object> row=new LinkedHashMap<>();row.put("name",name);try{body.run();row.put("passed",true);}catch(Exception|AssertionError e){row.put("passed",false);row.put("failure",e.getClass().getSimpleName()+": "+e.getMessage());}row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);}
    static void prepare(String restart)throws Exception {
        check("pristine_attachment_preserves_existing_cash",()->{String s=fresh();eq(number(s,"SELECT cash FROM paper_ledger_account"),10000000L);eq(number(s,"SELECT count(*) FROM paper_portfolio"),1L);eq(number(s,"SELECT current_cash*100 FROM paper_portfolio"),10000000L);});
        check("changed_cash_not_attached_or_reset",()->{String s=fresh("UPDATE paper_portfolio SET current_cash=99000");eq(number(s,"SELECT count(*) FROM paper_ledger_account"),0L);eq(number(s,"SELECT current_cash*100 FROM paper_portfolio"),9900000L);});
        check("missing_account_not_reseeded",()->{String s=fresh("DELETE FROM paper_portfolio");eq(number(s,"SELECT count(*) FROM paper_portfolio"),0L);reject(()->store(s).execute(1,approve("a",0,"b",Side.BUY,1)));});
        check("multiple_active_accounts_not_attached",()->{String s=fresh("INSERT INTO paper_portfolio(name,starting_cash,current_cash) VALUES('other',100000,100000)");eq(number(s,"SELECT count(*) FROM paper_ledger_account"),0L);});
        check("legacy_history_blocks_attachment",()->{
            String s=fresh("INSERT INTO market_signal(id,instrument_id,strategy_code,strategy_version,action,confidence_score,generated_at,data_as_of,valid_until,reference_price,acceptable_price_min,acceptable_price_max,maximum_slippage_percent) VALUES('00000000-0000-0000-0000-000000000001',1,'fixture','1','BUY',0,now(),now(),now()+interval '1 minute',100,99,101,1); INSERT INTO paper_order(id,paper_portfolio_id,signal_id,instrument_id,action,requested_quantity) VALUES('00000000-0000-0000-0000-000000000002',1,'00000000-0000-0000-0000-000000000001',1,'BUY',1)");
            eq(number(s,"SELECT count(*) FROM paper_ledger_account"),0L);eq(number(s,"SELECT count(*) FROM paper_order"),1L);
        });
        check("approval_reserves_without_debit",()->{String s=fresh();var r=store(s).execute(1,approve("a",0,"b",Side.BUY,10));eq(r.cashPaise(),10000000L);eq(r.reservedCashPaise(),101100L);});
        check("exact_command_retry_returns_original_receipt",()->{String s=fresh();var p=store(s);var cmd=approve("a",0,"b",Side.BUY,10);var first=p.execute(1,cmd);p.execute(1,fill("f",1,"b","f1",4,10));eq(p.execute(1,cmd),first);eq(number(s,"SELECT revision FROM paper_ledger_account"),2L);});
        check("conflicting_command_rolls_back",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));reject(()->p.execute(1,approve("a",0,"b",Side.BUY,11)));eq(number(s,"SELECT revision FROM paper_ledger_account"),1L);});
        check("partial_fills_and_legacy_cash_are_atomic",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));p.execute(1,fill("f1",1,"b","f1",4,10));var r=p.execute(1,fill("f2",2,"b","f2",6,10));eq(r.cashPaise(),9899980L);eq(r.reservedCashPaise(),0L);eq(r.orderStatus(),"FILLED");eq(number(s,"SELECT current_cash*100 FROM paper_portfolio"),r.cashPaise());eq(number(s,"SELECT count(*) FROM paper_ledger_fill"),2L);});
        check("fill_identity_cannot_debit_twice",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));p.execute(1,fill("f",1,"b","unique",4,10));reject(()->p.execute(1,fill("other",2,"b","unique",4,10)));eq(number(s,"SELECT revision FROM paper_ledger_account"),2L);});
        check("overfill_and_fee_overrun_rejected",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));reject(()->p.execute(1,fill("bad",1,"b","f",11,0)));reject(()->p.execute(1,fill("fee",1,"b","f",1,101)));eq(number(s,"SELECT revision FROM paper_ledger_account"),1L);});
        check("cancellation_releases_remaining_cash",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));p.execute(1,fill("f",1,"b","f",4,10));var r=p.execute(1,terminal("c",2,"b",false));eq(r.cashPaise(),9959990L);eq(r.reservedCashPaise(),0L);reject(()->p.execute(1,fill("late",3,"b","late",1,0)));});
        check("expiry_is_explicit_and_due",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,10));reject(()->p.execute(1,new Command("early",1,T,Kind.EXPIRE,0,null,null,null,null,"b")));eq(p.execute(1,terminal("expire",1,"b",true)).reservedCashPaise(),0L);});
        check("hold_records_decision_without_order",()->{String s=fresh();store(s).execute(1,approve("h",0,"hold",Side.HOLD,0));eq(number(s,"SELECT count(*) FROM paper_ledger_order"),0L);eq(number(s,"SELECT count(*) FROM paper_ledger_decision"),1L);});
        check("unowned_sell_rejected",()->{String s=fresh();reject(()->store(s).execute(1,approve("s",0,"s",Side.SELL,1)));eq(number(s,"SELECT revision FROM paper_ledger_account"),0L);});
        check("sell_reserves_owned_shares_and_partial_cancel_releases",()->{String s=fresh();var p=store(s);p.execute(1,approve("b",0,"b",Side.BUY,10));p.execute(1,fill("bf",1,"b","bf",10,0));p.execute(1,approve("s",2,"s",Side.SELL,6));p.execute(1,fill("sf",3,"s","sf",2,10));p.execute(1,terminal("sc",4,"s",false));eq(number(s,"SELECT quantity FROM paper_ledger_position"),8L);eq(number(s,"SELECT reserved FROM paper_ledger_position"),0L);eq(number(s,"SELECT cash FROM paper_ledger_account"),9919990L);});
        check("stale_revision_rejected",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,1));reject(()->p.execute(1,approve("b",0,"c",Side.BUY,1)));});
        check("rollback_after_projection_writes",()->{String s=fresh();var p=new PaperLedgerStore(()->connect(s),fixturePolicy(),c->{throw new SQLException("fixture rollback");});reject(()->p.execute(1,approve("a",0,"b",Side.BUY,10)));eq(number(s,"SELECT revision FROM paper_ledger_account"),0L);eq(number(s,"SELECT count(*) FROM paper_ledger_decision"),0L);});
        check("lost_ack_exact_retry_is_idempotent",()->{String s=fresh();var cmd=approve("a",0,"b",Side.BUY,10);var p=new PaperLedgerStore(()->connect(s),fixturePolicy(),c->{c.commit();throw new SQLException("simulated lost ack");});reject(()->p.execute(1,cmd));eq(store(s).execute(1,cmd).revision(),1L);eq(number(s,"SELECT count(*) FROM paper_ledger_command"),1L);});
        check("concurrent_approvals_serialize",()->{String s=fresh();var p=store(s);var pool=Executors.newFixedThreadPool(2);try{List<Future<Boolean>> fs=new ArrayList<>();for(String id:List.of("a","b"))fs.add(pool.submit(()->{try{p.execute(1,approve(id,0,id,Side.BUY,600));return true;}catch(IllegalArgumentException e){return false;}}));int n=0;for(var f:fs)if(f.get(15,TimeUnit.SECONDS))n++;eq(n,1);eq(number(s,"SELECT revision FROM paper_ledger_account"),1L);}finally{pool.shutdownNow();}});
        check("concurrent_duplicate_has_one_effect",()->{String s=fresh();var p=store(s);var cmd=approve("a",0,"b",Side.BUY,10);var pool=Executors.newFixedThreadPool(2);try{var one=pool.submit(()->p.execute(1,cmd));var two=pool.submit(()->p.execute(1,cmd));eq(one.get(15,TimeUnit.SECONDS),two.get(15,TimeUnit.SECONDS));eq(number(s,"SELECT count(*) FROM paper_ledger_command"),1L);}finally{pool.shutdownNow();}});
        check("lock_deadline_preserves_state",()->{String s=fresh();try(var c=connect(s);var q=c.createStatement()){c.setAutoCommit(false);q.execute("SELECT id FROM paper_portfolio WHERE id=1 FOR UPDATE");reject(()->store(s).execute(1,approve("a",0,"b",Side.BUY,1)));c.rollback();}eq(number(s,"SELECT revision FROM paper_ledger_account"),0L);});
        check("legacy_divergence_blocks",()->{String s=fresh();sql(s,"UPDATE paper_portfolio SET current_cash=99999");reject(()->store(s).execute(1,approve("a",0,"b",Side.BUY,1)));});
        check("append_only_evidence_rejects_edit_and_delete",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,1));reject(()->sql(s,"DELETE FROM paper_ledger_command"));reject(()->sql(s,"UPDATE paper_ledger_decision SET payload='{}'"));});
        check("order_corruption_blocks",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,1));sql(s,"UPDATE paper_ledger_order SET hash=repeat('0',64)");reject(()->p.execute(1,fill("f",1,"b","f",1,0)));});
        check("journal_projection_corruption_blocks",()->{String s=fresh();var p=store(s);p.execute(1,approve("a",0,"b",Side.BUY,1));sql(s,"UPDATE paper_ledger_account SET reserved=0");reject(()->p.execute(1,terminal("c",1,"b",false)));});
        check("more_than_256_commands_preserves_early_identity",()->{String s=fresh();var p=store(s);var first=approve("h0",0,"h0",Side.HOLD,0);var original=p.execute(1,first);for(int i=1;i<270;i++)p.execute(1,approve("h"+i,i,"h"+i,Side.HOLD,0));eq(p.execute(1,first),original);eq(number(s,"SELECT revision FROM paper_ledger_account"),270L);});
        check("prepare_restart_ledger",()->{initialize(restart,null);var p=store(restart);p.execute(1,approve("a",0,"b",Side.BUY,10));p.execute(1,fill("f",1,"b","f",4,10));});
    }
    public static void main(String[] args)throws Exception {
        if(args.length!=2 || !Set.of("--prepare","--recover").contains(args[0]) || !args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated phase/schema only");
        long start=System.nanoTime();String schema=args[1];
        if(args[0].equals("--prepare"))prepare(schema);
        else {
            check("fresh_jvm_recovery_preserves_balances",()->{eq(number(schema,"SELECT cash FROM paper_ledger_account"),9959990L);eq(number(schema,"SELECT reserved FROM paper_ledger_account"),60690L);eq(number(schema,"SELECT quantity FROM paper_ledger_position"),4L);});
            check("recovered_duplicate_does_not_debit",()->{eq(store(schema).execute(1,fill("f",1,"b","f",4,10)).revision(),2L);eq(number(schema,"SELECT revision FROM paper_ledger_account"),2L);});
            check("recovered_expiry_releases_reservation",()->{var r=store(schema).execute(1,terminal("expire",2,"b",true));eq(r.cashPaise(),9959990L);eq(r.reservedCashPaise(),0L);eq(r.revision(),3L);});
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();
        Map<String,Object> result=new LinkedHashMap<>();result.put("version",PaperLedgerStore.VERSION);result.put("phase",args[0]);result.put("schema",schema);result.put("status",failed==0?"ISOLATED_LEDGER_CHECKS_PASSED":"FAILED");result.put("checks",checks);result.put("checkCount",checks.size());result.put("failedCount",failed);result.put("elapsedSeconds",(System.nanoTime()-start)/1e9);result.put("applicationDatabaseAccessed",false);result.put("actionExecutionEnabled",false);result.put("syntheticDatabaseWritesPerformed",true);
        if(failed==0){result.put("cashPaise",number(schema,"SELECT cash FROM paper_ledger_account"));result.put("reservedCashPaise",number(schema,"SELECT reserved FROM paper_ledger_account"));result.put("revision",number(schema,"SELECT revision FROM paper_ledger_account"));}
        System.out.println(encode(result));if(failed>0)System.exit(2);
    }
}
