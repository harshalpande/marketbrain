package in.marketbrain.paper;

import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Explicit standalone entrypoint. Fixed disposable database aliases only; no Spring/application configuration. */
public final class PaperRecoveryVerification {
    private static final byte[] KEY = new byte[32];
    static { Arrays.fill(KEY, (byte)7); }
    private static final List<Map<String,Object>> checks = new ArrayList<>();
    static String identifier(String value) {
        if(value == null || !value.matches("[a-z][a-z0-9_]{0,62}")) throw new IllegalArgumentException("Invalid fixture identifier");
        return "\"" + value + "\"";
    }
    static Connection connection(String database, String schema, boolean audit) throws SQLException {
        if(!Set.of("paper_fixture", "paper_restore").contains(database) || !schema.matches("paper_verify_[a-f0-9]{32}"))
            throw new IllegalArgumentException("Disposable database/schema required");
        Connection c = DriverManager.getConnection("jdbc:postgresql://db:5432/"+database+"?connectTimeout=5&socketTimeout=20",
                audit ? "paper_audit_fixture" : "paper_fixture", "isolated_fixture_only");
        c.setSchema(schema);
        try(var s=c.createStatement()){s.execute("SET statement_timeout='10s'; SET lock_timeout='3s'");}
        return c;
    }
    static void execute(String database,String schema,boolean audit,String sql) throws SQLException {
        try(var c=connection(database,schema,audit);var s=c.createStatement()){s.execute(sql);}
    }
    static long number(String database,String schema,boolean audit,String sql) throws SQLException {
        try(var c=connection(database,schema,audit);var s=c.createStatement();var r=s.executeQuery(sql)){if(!r.next())throw new AssertionError("Missing row");return r.getLong(1);}
    }
    /** Exact SQLSTATE is required: syntax, missing objects and connection errors do not count as permission rejection. */
    static void denied(Check body)throws Exception {
        try { body.run(); } catch(SQLException e) { if("42501".equals(e.getSQLState()))return; throw e; }
        throw new AssertionError("Expected insufficient_privilege");
    }
    static Map<String,String> snapshot(String database,String schema)throws Exception {
        var result=new TreeMap<String,String>();
        try(var c=connection(database,schema,false)){
            c.setReadOnly(true);c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);c.setAutoCommit(false);
            try(var s=c.prepareStatement("SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname=? ORDER BY tablename LIMIT 257")){
                s.setString(1,schema);
                try(var tables=s.executeQuery()){
                    while(tables.next()){
                        if(result.size()>=256)throw new AssertionError("Fixture table bound exceeded");
                        String table=tables.getString(1);var values=new ArrayList<String>();
                        try(var rows=c.createStatement();var r=rows.executeQuery("SELECT row_to_json(t)::text FROM "+identifier(schema)+"."+identifier(table)+" t ORDER BY row_to_json(t)::text COLLATE \"C\" LIMIT 1001")){
                            while(r.next()){if(values.size()>=1000)throw new AssertionError("Fixture row bound exceeded");values.add(r.getString(1));}
                        }
                        result.put(table,PaperLedgerStore.hash(encode(values)));
                    }
                }
                c.commit();
            }catch(Exception e){c.rollback();throw e;}
        }
        if(result.isEmpty())throw new AssertionError("Empty snapshot");
        return result;
    }
    static final class Fixture {
        final PaperApprovalReview review; final PaperApprovalDelivery delivery;
        final AtomicInteger sends=new AtomicInteger(), quotes=new AtomicInteger();
        Fixture(String database,String schema){
            PaperLedgerStore.Connections connections=()->connection(database,schema,false);
            Clock clock=Clock.fixed(T,ZoneOffset.UTC);
            review=new PaperApprovalReview(connections,p->{quotes.incrementAndGet();return PaperApprovalVerification.quote();},clock,PaperApprovalVerification.POLICY);
            delivery=new PaperApprovalDelivery(connections,review,(p,t)->{sends.incrementAndGet();return "12";},clock,KEY);
        }
    }
    static Tokens tokens(String database,String schema,String id)throws Exception {
        try(var c=connection(database,schema,false);var s=c.prepareStatement("SELECT encrypted_tokens FROM paper_approval_delivery WHERE proposal_id=?")){
            s.setString(1,id);try(var r=s.executeQuery()){if(!r.next())throw new AssertionError("Missing ciphertext");return PaperLedgerStore.decode(new PaperApprovalDelivery.Vault(KEY).open(r.getString(1),id),Tokens.class);}
        }
    }
    static void seed(String schema)throws Exception {
        PaperStorageVerification.init(schema);
        sql(schema,"INSERT INTO telegram_binding(binding_key,telegram_user_id,telegram_chat_id) VALUES('PRIMARY',111,222)");
        PaperApprovalStorage.bind(()->connection("paper_fixture",schema,false),KEY);
        var f=new Fixture("paper_fixture",schema);
        for(String id:List.of("pending","sent","uncertain","sending"))f.delivery.enqueue(PaperApprovalVerification.proposal(id,Side.BUY,1,0));
        eq(f.delivery.dispatch("sent"),"SENT");
        eq(f.review.process(new Callback("accepted-before-backup",111,222,true,tokens("paper_fixture",schema,"sent").accept())).status(),"ACCEPTED_EXECUTION_BLOCKED");
        sql(schema,"UPDATE paper_approval_delivery SET state='SENDING',attempt_id=proposal_id,attempted_at=created_at WHERE proposal_id IN ('uncertain','sending'); UPDATE paper_approval_delivery SET state='UNCERTAIN' WHERE proposal_id='uncertain'");
        PaperApprovalVerification.unchanged(schema);
    }
    static void auditRole(String schema)throws Exception {
        execute("paper_restore",schema,false,"CREATE ROLE paper_audit_fixture LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD 'isolated_fixture_only'; REVOKE ALL ON DATABASE paper_restore FROM PUBLIC; GRANT CONNECT ON DATABASE paper_restore TO paper_audit_fixture; REVOKE CREATE ON SCHEMA public FROM PUBLIC; REVOKE ALL ON SCHEMA "+identifier(schema)+" FROM PUBLIC; REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "+identifier(schema)+" FROM PUBLIC; GRANT USAGE ON SCHEMA "+identifier(schema)+" TO paper_audit_fixture");
        execute("paper_restore",schema,false,resource("/paper/approval-audit-v1.sql"));
        execute("paper_restore",schema,false,"GRANT SELECT ON paper_review_audit,paper_delivery_audit TO paper_audit_fixture");
    }
    static void check(String name,Check body){
        long start=System.nanoTime();var row=new LinkedHashMap<String,Object>();row.put("name",name);
        try{body.run();row.put("passed",true);}catch(Exception|AssertionError e){row.put("passed",false);row.put("failure",e.getClass().getSimpleName());}
        row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);
    }
    public static void main(String[] args)throws Exception {
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0])||!args[1].matches("paper_verify_[a-f0-9]{32}"))throw new IllegalArgumentException("Isolated phase/schema required");
        String schema=args[1];long start=System.nanoTime();var r=new LinkedHashMap<String,Object>();
        if(args[0].equals("--prepare")){
            check("seed_backup_with_review_and_four_delivery_states",()->{seed(schema);eq(number("paper_fixture",schema,false,"SELECT count(*) FROM paper_approval_delivery"),4L);eq(number("paper_fixture",schema,false,"SELECT count(*) FROM paper_approval_proposal WHERE receipt IS NOT NULL"),1L);});
            check("snapshot_covers_account_tokens_ciphertext_and_binding",()->{var s=snapshot("paper_fixture",schema);if(!s.keySet().containsAll(List.of("paper_portfolio","paper_ledger_account","paper_approval_proposal","paper_approval_token","paper_approval_delivery","paper_approval_key_binding","telegram_binding")))throw new AssertionError("Incomplete snapshot");r.put("snapshotHash",PaperLedgerStore.hash(encode(s)));r.put("snapshotTableCount",s.size());});
        }else{
            var source=snapshot("paper_fixture",schema);
            check("restored_rows_match_source_snapshot",()->{var restored=snapshot("paper_restore",schema);eq(restored,source);r.put("snapshotHash",PaperLedgerStore.hash(encode(restored)));r.put("snapshotTableCount",restored.size());});
            check("original_key_opens_restored_tokens_without_reissue",()->{PaperApprovalStorage.verify(()->connection("paper_restore",schema,false),KEY);eq(tokens("paper_restore",schema,"sent"),tokens("paper_fixture",schema,"sent"));eq(number("paper_restore",schema,false,"SELECT count(*) FROM paper_approval_token"),8L);});
            check("wrong_key_cannot_replace_restored_binding",()->{byte[] wrong=new byte[32];Arrays.fill(wrong,(byte)8);reject(()->PaperApprovalStorage.bind(()->connection("paper_restore",schema,false),wrong));PaperApprovalStorage.verify(()->connection("paper_restore",schema,false),KEY);});
            check("restored_receipt_and_ciphertext_remain_immutable",()->{reject(()->execute("paper_restore",schema,false,"UPDATE paper_approval_proposal SET receipt='{}' WHERE id='sent'"));reject(()->execute("paper_restore",schema,false,"UPDATE paper_approval_delivery SET encrypted_tokens='tampered' WHERE proposal_id='pending'"));});
            check("restored_binding_quarantined_before_any_dispatch",()->{execute("paper_restore",schema,false,"UPDATE telegram_binding SET active=FALSE WHERE binding_key='PRIMARY'");eq(number("paper_restore",schema,false,"SELECT count(*) FROM telegram_binding WHERE active"),0L);});
            check("quarantine_blocks_pending_and_attempted_resends",()->{var f=new Fixture("paper_restore",schema);eq(f.delivery.dispatch("pending"),"REVOKED");for(String id:List.of("sent","uncertain","sending"))eq(f.delivery.dispatch(id),id.toUpperCase(Locale.ROOT));eq(f.sends.get(),0);});
            check("quarantine_blocks_callback_without_quote",()->{var f=new Fixture("paper_restore",schema);reject(()->f.review.process(new Callback("after-restore",111,222,true,tokens("paper_restore",schema,"pending").accept())));eq(f.quotes.get(),0);});
            check("audit_role_reads_only_redacted_views",()->{auditRole(schema);eq(number("paper_restore",schema,true,"SELECT cash FROM paper_review_audit WHERE portfolio_id=1"),10000000L);eq(number("paper_restore",schema,true,"SELECT count(*) FROM paper_delivery_audit"),4L);eq(number("paper_restore",schema,true,"SELECT count(*) FROM pg_roles WHERE rolname=current_user AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls"),1L);});
            check("audit_role_cannot_read_secrets_or_private_identity",()->{for(String table:List.of("paper_approval_token","paper_approval_key_binding","paper_approval_delivery","paper_approval_proposal","telegram_binding"))denied(()->execute("paper_restore",schema,true,"SELECT * FROM "+identifier(table)+" LIMIT 1"));});
            check("audit_role_cannot_change_money_reviews_or_orders",()->{for(String sql:List.of("UPDATE paper_review_audit SET cash=1 WHERE portfolio_id=1","UPDATE paper_approval_proposal SET receipt='{}' WHERE id='pending'","UPDATE paper_approval_delivery SET state='SENT' WHERE proposal_id='pending'","DELETE FROM paper_approval_token","TRUNCATE paper_ledger_order","INSERT INTO paper_order DEFAULT VALUES"))denied(()->execute("paper_restore",schema,true,sql));});
            check("audit_role_cannot_ddl_escalate_or_lock_as_writer",()->{for(String sql:List.of("CREATE TABLE forbidden(id int)","CREATE TEMP TABLE forbidden(id int)","ALTER TABLE paper_approval_delivery DISABLE TRIGGER ALL","SET ROLE paper_fixture","SELECT * FROM paper_ledger_account FOR UPDATE"))denied(()->execute("paper_restore",schema,true,sql));});
            check("source_unchanged_and_restored_money_preserved",()->{eq(snapshot("paper_fixture",schema),source);eq(number("paper_restore",schema,false,"SELECT cash FROM paper_ledger_account"),10000000L);eq(number("paper_restore",schema,false,"SELECT reserved+revision FROM paper_ledger_account"),0L);eq(number("paper_restore",schema,false,"SELECT count(*) FROM paper_ledger_order"),0L);eq(number("paper_restore",schema,false,"SELECT count(*) FROM paper_ledger_fill"),0L);});
        }
        long failed=checks.stream().filter(c->!Boolean.TRUE.equals(c.get("passed"))).count();
        r.put("version","PAPER_RECOVERY_REVIEW_V1");r.put("status",failed==0?"ISOLATED_RECOVERY_CHECKS_PASSED":"FAILED");r.put("phase",args[0]);r.put("schema",schema);r.put("checks",checks);r.put("checkCount",checks.size());r.put("failedCount",failed);r.put("elapsedSeconds",(System.nanoTime()-start)/1e9);
        r.put("applicationDatabaseAccessed",false);r.put("actionExecutionEnabled",false);r.put("approvalWriterReady",false);r.put("syntheticDatabaseWritesPerformed",true);r.put("providerCalls",0);r.put("telegramCalls",0);r.put("modelCalls",0);
        System.out.println(encode(r));if(failed>0)System.exit(2);
    }
}
