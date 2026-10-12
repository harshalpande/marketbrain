package in.marketbrain.paper;

import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperApprovalVerification.POLICY;
import static in.marketbrain.paper.PaperApprovalVerification.proposal;
import static in.marketbrain.paper.PaperApprovalVerification.quote;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;
import static in.marketbrain.paper.PaperRecoveryVerification.denied;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Disposable, fixed db alias only. No application configuration, real identity, key or network provider. */
public final class PaperWriterVerification {
    static final String WRITER="paper_review_fixture", HELPER="paper_review_lock_fixture", STRANGER="paper_stranger_fixture";
    private static final List<Map<String,Object>> checks=new ArrayList<>();
    static String schema(String s){
        if(s==null||!s.matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Disposable schema required");
        return "\""+s+"\"";
    }
    static String candidateSql(String s)throws Exception {return resource("/paper/approval-writer-v1.sql").replace("__SCHEMA__",schema(s));}
    static Connection writer(String s,String role)throws SQLException {
        schema(s);if(!Set.of(WRITER,STRANGER).contains(role))throw new IllegalArgumentException("Fixture role only");
        Connection c=DriverManager.getConnection("jdbc:postgresql://db:5432/paper_fixture?connectTimeout=5&socketTimeout=20",role,"isolated_fixture_only");
        c.setSchema(s);try(var q=c.createStatement()){q.execute("SET statement_timeout='10s'; SET lock_timeout='3s'");}return c;
    }
    static void executeAs(String s,String role,String query)throws Exception {
        try(var c=writer(s,role);var q=c.createStatement()){q.execute(query);}
    }
    /** Fixture installer only. Role names and credentials here must never be copied into application setup. */
    static void install(String s)throws Exception {
        String quoted=schema(s);
        PaperStorageVerification.init(s);
        sql(s,"INSERT INTO telegram_binding(binding_key,telegram_user_id,telegram_chat_id) VALUES('PRIMARY',111,222)");
        try(var c=connect(s);var q=c.createStatement()){
            c.setAutoCommit(false);
            try {
                q.execute("CREATE ROLE "+HELPER+" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS; "
                        +"CREATE ROLE "+WRITER+" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD 'isolated_fixture_only'; "
                        +"CREATE ROLE "+STRANGER+" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD 'isolated_fixture_only'; "
                        +"REVOKE ALL ON DATABASE paper_fixture FROM PUBLIC; GRANT CONNECT ON DATABASE paper_fixture TO "+WRITER+","+STRANGER+"; "
                        +"REVOKE CREATE ON SCHEMA public FROM PUBLIC; REVOKE ALL ON SCHEMA "+quoted+" FROM PUBLIC; "
                        +"REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "+quoted+" FROM PUBLIC; "
                        +"GRANT USAGE ON SCHEMA "+quoted+" TO "+WRITER+","+HELPER+","+STRANGER);
                // Trusted review engine needs proposal/policy evidence. No delivery ciphertext or private key table.
                String readers="paper_approval_proposal,paper_approval_token,telegram_binding,paper_portfolio,paper_ledger_account,paper_ledger_command,paper_ledger_position,instrument";
                q.execute("GRANT SELECT ON "+readers+" TO "+WRITER+","+HELPER);
                // PostgreSQL row locks require UPDATE on at least one column. Only the NOLOGIN helper gets it.
                q.execute("GRANT UPDATE(id) ON paper_portfolio TO "+HELPER+"; GRANT UPDATE(portfolio_id) ON paper_ledger_account TO "+HELPER
                        +"; GRANT UPDATE(binding_key) ON telegram_binding TO "+HELPER+"; GRANT UPDATE(id,decided_token,callback_id,receipt) ON paper_approval_proposal TO "+HELPER);
                q.execute(candidateSql(s));
                // Ownership transfer requires CREATE temporarily; never leave it granted.
                q.execute("GRANT CREATE ON SCHEMA "+quoted+" TO "+HELPER
                        +"; ALTER FUNCTION paper_review_lock(text,bigint,bigint) OWNER TO "+HELPER
                        +"; ALTER FUNCTION paper_review_record(text,bigint,bigint,text,text) OWNER TO "+HELPER
                        +"; REVOKE CREATE ON SCHEMA "+quoted+" FROM "+HELPER
                        +"; GRANT EXECUTE ON FUNCTION paper_review_lock(text,bigint,bigint),paper_review_record(text,bigint,bigint,text,text) TO "+WRITER);
                c.commit();
            } catch(Exception e){c.rollback();throw e;}
        }
    }
    static PaperApprovalReview review(String s,QuoteSource source,Clock clock){return PaperApprovalReview.restrictedWriter(()->writer(s,WRITER),source,clock,POLICY);}
    static Tokens issue(String s,String id)throws Exception {return new PaperApprovalReview(()->connect(s),p->quote(),Clock.fixed(T,ZoneOffset.UTC),POLICY).issue(proposal(id,Side.BUY,1,0));}
    static Callback callback(String id,String token){return new Callback(id,111,222,true,token);}
    static void record(String s,String token,long user,long chat,String callback,String receipt)throws Exception {
        try(var c=writer(s,WRITER)) {PaperApprovalReview.begin(c);try{PaperApprovalReview.writerCommand(c,"SELECT paper_review_record(?,?,?,?,?)",PaperLedgerStore.hash(token),user,chat,callback,receipt);c.commit();}catch(Exception e){c.rollback();throw e;}}
    }
    static Receipt receipt(String id,String status){return new Receipt(PaperApprovalReview.VERSION,status,id,0,POLICY.id(),T,"a".repeat(64),false);}
    static void check(String name,Check body){
        long start=System.nanoTime();var row=new LinkedHashMap<String,Object>();row.put("name",name);
        try{body.run();row.put("passed",true);}catch(Exception|AssertionError e){row.put("passed",false);row.put("failure",e.getClass().getSimpleName());String message=Objects.toString(e.getMessage(),"");row.put("failureMessage",message.substring(0,Math.min(message.length(),1000)));if(e instanceof SQLException sql)row.put("sqlState",sql.getSQLState());}
        row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);
    }
    static void prepare(String s){
        check("install_non_owner_writer_and_no_login_helper",()->{install(s);eq(number(s,"SELECT count(*) FROM pg_roles WHERE rolname IN ('"+WRITER+"','"+HELPER+"') AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls"),2L);eq(number(s,"SELECT count(*) FROM pg_roles WHERE rolname='"+HELPER+"' AND NOT rolcanlogin"),1L);});
        check("accept_records_review_without_execution",()->{var t=issue(s,"accept");var r=review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).process(callback("accept",t.accept()));eq(r.status(),"ACCEPTED_EXECUTION_BLOCKED");eq(r.actionExecutionEnabled(),false);sql(s,"CREATE TABLE fixture_writer_token(value text); INSERT INTO fixture_writer_token VALUES('"+t.accept()+"')");});
        check("reject_skips_quote_and_records_once",()->{var t=issue(s,"reject");var r=review(s,p->{throw new AssertionError("Quote on reject");},Clock.fixed(T,ZoneOffset.UTC));var one=r.process(callback("reject",t.reject()));eq(one.status(),"REJECTED");eq(r.process(callback("reject-again",t.reject())),one);reject(()->r.process(callback("opposing",t.accept())));});
        check("wrong_identity_and_unknown_token_stop_before_quote",()->{var t=issue(s,"identity");AtomicInteger calls=new AtomicInteger();var r=review(s,p->{calls.incrementAndGet();return quote();},Clock.fixed(T,ZoneOffset.UTC));reject(()->r.process(new Callback("wrong",999,222,true,t.accept())));reject(()->r.process(callback("unknown","a".repeat(43))));eq(calls.get(),0);});
        check("private_chat_required",()->{var r=review(s,p->{throw new AssertionError();},Clock.fixed(T,ZoneOffset.UTC));reject(()->r.process(new Callback("public",111,222,false,"a".repeat(43))));});
        check("binding_revoked_during_quote_blocks_commit",()->{var t=issue(s,"revoked");try{var r=review(s,p->{sql(s,"UPDATE telegram_binding SET active=FALSE");return quote();},Clock.fixed(T,ZoneOffset.UTC));reject(()->r.process(callback("revoked",t.accept())));eq(number(s,"SELECT count(*) FROM paper_approval_proposal WHERE id='revoked' AND receipt IS NOT NULL"),0L);}finally{sql(s,"UPDATE telegram_binding SET active=TRUE");}});
        check("quote_expiry_is_rechecked",()->{var t=issue(s,"expiry");var time=new PaperApprovalVerification.Time();var r=review(s,p->{time.at=T.plusSeconds(120);return quote();},time);eq(r.process(callback("expiry",t.accept())).status(),"EXPIRED");});
        check("quote_failure_and_out_of_zone_cannot_accept",()->{var t=issue(s,"unavailable");eq(review(s,p->{throw new IllegalStateException();},Clock.fixed(T,ZoneOffset.UTC)).process(callback("unavailable",t.accept())).status(),"QUOTE_UNAVAILABLE");t=issue(s,"zone");eq(review(s,p->new MarketQuote(1,"FIXTURE","FIXTURE",11000,T,T),Clock.fixed(T,ZoneOffset.UTC)).process(callback("zone",t.accept())).status(),"RISK_BLOCKED");});
        check("account_change_during_quote_is_detected",()->{var t=issue(s,"changed");try{var r=review(s,p->{sql(s,"UPDATE paper_portfolio SET current_cash=99999");return quote();},Clock.fixed(T,ZoneOffset.UTC));eq(r.process(callback("changed",t.accept())).status(),"ACCOUNT_INCONSISTENT");}finally{sql(s,"UPDATE paper_portfolio SET current_cash=100000");}});
        check("concurrent_duplicate_has_one_receipt",()->{var t=issue(s,"race");var r=review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC));var pool=Executors.newFixedThreadPool(2);try{var a=pool.submit(()->r.process(callback("race-a",t.accept())));var b=pool.submit(()->r.process(callback("race-b",t.accept())));eq(a.get(15,TimeUnit.SECONDS),b.get(15,TimeUnit.SECONDS));eq(number(s,"SELECT count(*) FROM paper_approval_proposal WHERE id='race' AND receipt IS NOT NULL"),1L);}finally{pool.shutdownNow();}});
        check("writer_cannot_issue_proposals_or_tokens",()->{reject(()->review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).issue(proposal("no-issue",Side.BUY,1,0)));for(String table:List.of("paper_approval_proposal","paper_approval_token"))denied(()->executeAs(s,WRITER,"INSERT INTO "+table+" DEFAULT VALUES"));});
        check("writer_cannot_change_cash_reserves_positions_or_orders",()->{for(String query:List.of("UPDATE paper_portfolio SET current_cash=1 WHERE id=1","UPDATE paper_ledger_account SET cash=1,reserved=0 WHERE portfolio_id=1","UPDATE paper_ledger_position SET quantity=1","INSERT INTO paper_ledger_order DEFAULT VALUES","INSERT INTO paper_ledger_fill DEFAULT VALUES","INSERT INTO paper_order DEFAULT VALUES","DELETE FROM paper_ledger_command","TRUNCATE paper_ledger_account"))denied(()->executeAs(s,WRITER,query));});
        check("writer_cannot_directly_edit_reviews_tokens_or_binding",()->{for(String query:List.of("UPDATE paper_approval_proposal SET receipt='{}' WHERE id='identity'","UPDATE paper_approval_proposal SET payload='{}' WHERE id='identity'","DELETE FROM paper_approval_token","UPDATE telegram_binding SET active=FALSE","UPDATE paper_approval_delivery SET state='SENT'"))denied(()->executeAs(s,WRITER,query));});
        check("writer_cannot_read_ciphertext_or_key_binding",()->{for(String table:List.of("paper_approval_delivery","paper_approval_key_binding"))denied(()->executeAs(s,WRITER,"SELECT * FROM "+table+" LIMIT 1"));});
        check("writer_cannot_ddl_escalate_or_lock_base_tables",()->{for(String query:List.of("CREATE TABLE forbidden(id int)","CREATE TEMP TABLE forbidden(id int)","SET ROLE "+HELPER,"SET ROLE paper_fixture","ALTER TABLE paper_approval_proposal DISABLE TRIGGER ALL","SELECT * FROM paper_portfolio FOR UPDATE","SELECT * FROM paper_approval_proposal FOR UPDATE"))denied(()->executeAs(s,WRITER,query));});
        check("public_cannot_call_privileged_functions",()->{for(String query:List.of("SELECT paper_review_lock(repeat('a',64),111,222)","SELECT paper_review_record(repeat('a',64),111,222,'x','{}')"))denied(()->executeAs(s,STRANGER,query));});
        check("command_checks_recipient_and_token_itself",()->{var t=issue(s,"command-auth");denied(()->record(s,t.accept(),999,222,"wrong",encode(receipt("command-auth","ACCEPTED_EXECUTION_BLOCKED"))));denied(()->record(s,"a".repeat(43),111,222,"unknown",encode(receipt("command-auth","ACCEPTED_EXECUTION_BLOCKED"))));});
        check("command_rejects_execution_and_wrong_receipt_identity",()->{var t=issue(s,"command-shape");String good=encode(receipt("command-shape","ACCEPTED_EXECUTION_BLOCKED"));for(String bad:List.of(good.replace("false","true"),good.replace("command-shape","other"),good.replace("ACCEPTED_EXECUTION_BLOCKED","FILLED"),"{}","null"))reject(()->record(s,t.accept(),111,222,"invalid",bad));eq(number(s,"SELECT count(*) FROM paper_approval_proposal WHERE id='command-shape' AND receipt IS NOT NULL"),0L);});
        check("reject_token_cannot_become_accept_receipt",()->{var t=issue(s,"action-shape");reject(()->record(s,t.reject(),111,222,"action",encode(receipt("action-shape","ACCEPTED_EXECUTION_BLOCKED"))));});
        check("callback_collision_rolls_back_terminal_write",()->{var t=issue(s,"collision");reject(()->review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).process(callback("accept",t.accept())));eq(number(s,"SELECT count(*) FROM paper_approval_proposal WHERE id='collision' AND receipt IS NOT NULL"),0L);});
        check("lock_timeout_leaves_review_unwritten",()->{var t=issue(s,"timeout");try(var c=connect(s);var q=c.createStatement()){c.setAutoCommit(false);q.execute("SELECT id FROM paper_portfolio WHERE id=1 FOR UPDATE");try{review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).process(callback("timeout",t.accept()));throw new AssertionError("Expected lock timeout");}catch(SQLException e){eq(e.getSQLState(),"55P03");}c.rollback();}eq(number(s,"SELECT count(*) FROM paper_approval_proposal WHERE id='timeout' AND receipt IS NOT NULL"),0L);});
        check("fixed_search_path_and_helper_have_no_money_privilege",()->{eq(number(s,"SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='"+s+"' AND p.proname IN ('paper_review_lock','paper_review_record') AND p.prosecdef AND pg_get_userbyid(p.proowner)='"+HELPER+"' AND array_to_string(p.proconfig,',') LIKE 'search_path=pg_catalog,%pg_temp'"),2L);eq(number(s,"SELECT has_column_privilege('"+HELPER+"','paper_portfolio','current_cash','UPDATE')::int + has_column_privilege('"+HELPER+"','paper_ledger_account','cash','UPDATE')::int + has_schema_privilege('"+HELPER+"','"+s+"','CREATE')::int"),0L);});
        check("all_reviews_preserve_money_and_no_orders",()->PaperApprovalVerification.unchanged(s));
    }
    public static void main(String[] args)throws Exception {
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0]))throw new IllegalArgumentException("Isolated phase required");schema(args[1]);
        String s=args[1];long started=System.nanoTime();
        if(args[0].equals("--prepare"))prepare(s);else{
            check("restart_replay_returns_saved_receipt_without_quote",()->{String token;try(var c=connect(s);var q=c.createStatement();var r=q.executeQuery("SELECT value FROM fixture_writer_token")){if(!r.next())throw new AssertionError("Missing fixture token");token=r.getString(1);}eq(review(s,p->{throw new AssertionError("Quote on replay");},Clock.fixed(T.plusSeconds(999),ZoneOffset.UTC)).process(callback("restart",token)).status(),"ACCEPTED_EXECUTION_BLOCKED");});
            check("restart_permissions_and_new_review_work",()->{denied(()->executeAs(s,WRITER,"UPDATE paper_portfolio SET current_cash=1 WHERE id=1"));var t=issue(s,"after-restart");eq(review(s,p->quote(),Clock.fixed(T,ZoneOffset.UTC)).process(callback("after-restart",t.accept())).status(),"ACCEPTED_EXECUTION_BLOCKED");});
            check("restart_preserves_money_and_no_orders",()->PaperApprovalVerification.unchanged(s));
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();var r=new LinkedHashMap<String,Object>();
        r.put("version","PAPER_WRITER_REVIEW_V1");r.put("status",failed==0?"ISOLATED_WRITER_CHECKS_PASSED":"FAILED");r.put("phase",args[0]);r.put("schema",s);r.put("checks",checks);r.put("checkCount",checks.size());r.put("failedCount",failed);r.put("elapsedSeconds",(System.nanoTime()-started)/1e9);
        r.put("applicationDatabaseAccessed",false);r.put("actionExecutionEnabled",false);r.put("applicationWriterActivated",false);r.put("syntheticDatabaseWritesPerformed",true);r.put("providerCalls",0);r.put("telegramCalls",0);r.put("modelCalls",0);
        if(failed==0){r.put("cashPaise",number(s,"SELECT cash FROM paper_ledger_account"));r.put("reservedCashPaise",number(s,"SELECT reserved FROM paper_ledger_account"));r.put("ledgerRevision",number(s,"SELECT revision FROM paper_ledger_account"));r.put("orderCount",number(s,"SELECT count(*) FROM paper_ledger_order"));r.put("fillCount",number(s,"SELECT count(*) FROM paper_ledger_fill"));}
        System.out.println(encode(r));if(failed>0)System.exit(2);
    }
}
