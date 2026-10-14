package in.marketbrain.paper;

import java.nio.file.*;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import in.marketbrain.paper.PaperLedgerVerification.Check;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperApprovalVerification.POLICY;
import static in.marketbrain.paper.PaperApprovalVerification.proposal;
import static in.marketbrain.paper.PaperApprovalVerification.quote;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;

/** Disposable db only, in the fixture database container's network namespace. No host files or real messages. */
public final class PaperTelegramVerification {
    private static final String SECRET = "ab".repeat(32); // Synthetic fixture only, never deploy this credential.
    private static final List<Map<String,Object>> checks = new ArrayList<>();
    private static Path credential;
    private static PaperWriterConnector.Target target;

    static PaperApprovalCallback callback(QuoteSource quotes, Clock clock) {
        return PaperReviewWiring.callback(target, credential, quotes, clock, POLICY);
    }
    static Connection writer() throws SQLException {
        return new PaperWriterConnector(target, () -> PaperReviewWiring.readCredential(credential), true).open();
    }
    static String handle(PaperApprovalCallback cb, String id, String token) throws SQLException {
        return cb.handle(id, 111, 222, "private", "mbp:" + token);
    }
    static Tokens issue(String schema, String id) throws Exception { return PaperWriterVerification.issue(schema, id); }
    static void check(String name, Check body) {
        long start = System.nanoTime(); var row = new LinkedHashMap<String,Object>(); row.put("name", name);
        try { body.run(); row.put("passed", true); }
        catch (Exception | AssertionError failure) {
            row.put("passed", false); row.put("failure", failure.getClass().getSimpleName());
            if (failure instanceof SQLException sql) row.put("sqlState", sql.getSQLState());
        }
        row.put("elapsedMillis", (System.nanoTime()-start)/1e6); checks.add(row);
    }
    static void configure(String schema) throws Exception {
        long oid = number(schema, "SELECT oid FROM pg_database WHERE datname='paper_fixture'");
        target = new PaperWriterConnector.Target("127.0.0.1",5432,"paper_fixture",oid,
                PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null);
        credential = Files.createTempFile("synthetic-review-", ".secret");
        Files.writeString(credential, SECRET);
    }
    static void prepare(String schema) throws Exception {
        check("install_fixture_and_authenticate_real_connector", () -> {
            PaperWriterVerification.install(schema);
            sql(schema, "ALTER ROLE " + PaperWriterVerification.WRITER + " RENAME TO " + PaperWriterConnector.ROLE
                    + "; ALTER ROLE " + PaperWriterConnector.ROLE + " PASSWORD '" + SECRET + "'"
                    + "; ALTER ROLE " + PaperWriterConnector.ROLE + " SET search_path TO " + PaperWriterVerification.schema(schema));
            configure(schema);
            try (var c = writer()) { eq(c.getMetaData().getUserName(), PaperWriterConnector.ROLE); }
        });
        check("accept_callback_records_without_execution", () -> {
            var t = issue(schema, "bridge-accept");
            String result = handle(callback(p -> quote(), Clock.fixed(T,ZoneOffset.UTC)), "accept", t.accept());
            eq(result, "PAPER review accepted. Execution remains disabled; no order or reservation created.");
            sql(schema, "CREATE TABLE bridge_restart_token(value text); INSERT INTO bridge_restart_token VALUES('" + t.accept() + "')");
        });
        check("reject_callback_skips_quote", () -> {
            var t = issue(schema, "bridge-reject");
            eq(handle(callback(p -> {throw new AssertionError("No quote on reject");}, Clock.fixed(T,ZoneOffset.UTC)),
                    "reject", t.reject()), "PAPER proposal rejected. No trade created.");
        });
        check("duplicate_callback_reuses_receipt", () -> {
            var t = issue(schema, "bridge-duplicate");
            handle(callback(p -> quote(),Clock.fixed(T,ZoneOffset.UTC)), "dup-first", t.accept());
            String replay = handle(callback(p -> {throw new AssertionError("No quote on replay");},Clock.fixed(T.plusSeconds(999),ZoneOffset.UTC)), "dup-second", t.accept());
            eq(replay, "PAPER review accepted. Execution remains disabled; no order or reservation created.");
            eq(number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE id='bridge-duplicate' AND receipt IS NOT NULL"),1L);
        });
        check("opposing_action_cannot_replace_receipt", () -> {
            var t = issue(schema, "bridge-opposing"); var cb = callback(p -> quote(),Clock.fixed(T,ZoneOffset.UTC));
            handle(cb, "opposing-reject", t.reject()); reject(() -> handle(cb,"opposing-accept",t.accept()));
        });
        check("group_and_malformed_callbacks_stop_before_credential_read", () -> {
            var cb = PaperReviewWiring.callback(target,credential.resolveSibling("missing"),p -> {throw new AssertionError();},Clock.fixed(T,ZoneOffset.UTC),POLICY);
            reject(() -> cb.handle("group",111,222,"group","mbp:"+"a".repeat(43)));
            reject(() -> cb.handle("invalid",111,222,"private","invalid"));
        });
        check("wrong_user_and_unknown_token_cannot_record", () -> {
            var t = issue(schema,"bridge-identity"); var cb = callback(p -> {throw new AssertionError();},Clock.fixed(T,ZoneOffset.UTC));
            reject(() -> cb.handle("wrong",999,222,"private","mbp:"+t.accept()));
            reject(() -> handle(cb,"unknown","a".repeat(43)));
            eq(number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE id='bridge-identity' AND receipt IS NOT NULL"),0L);
        });
        check("expired_callback_cannot_accept", () -> {
            var t = issue(schema,"bridge-expired");
            eq(handle(callback(p -> {throw new AssertionError();},Clock.fixed(T.plusSeconds(120),ZoneOffset.UTC)),"expired",t.accept()),
                    "PAPER proposal expired. No trade created.");
        });
        check("unavailable_quote_blocks_accept", () -> {
            var t = issue(schema,"bridge-quote");
            eq(handle(callback(p -> {throw new IllegalStateException();},Clock.fixed(T,ZoneOffset.UTC)),"quote",t.accept()),
                    "PAPER review blocked: QUOTE_UNAVAILABLE. No trade created.");
        });
        check("credential_rotation_is_read_on_next_connection", () -> {
            try { Files.writeString(credential,"cd".repeat(32)); reject(() -> {try(var c=writer()){throw new AssertionError("Wrong credential accepted");}}); }
            finally { Files.writeString(credential,SECRET); }
            try(var c=writer()){eq(c.getMetaData().getUserName(),PaperWriterConnector.ROLE);}
        });
        check("nologin_revocation_prevents_callback_and_preserves_pending", () -> {
            var t=issue(schema,"bridge-revoked");
            try {
                sql(schema,"ALTER ROLE "+PaperWriterConnector.ROLE+" NOLOGIN");
                reject(() -> handle(callback(p -> quote(),Clock.fixed(T,ZoneOffset.UTC)),"revoked",t.accept()));
                eq(number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE id='bridge-revoked' AND receipt IS NOT NULL"),0L);
            } finally { sql(schema,"ALTER ROLE "+PaperWriterConnector.ROLE+" LOGIN"); }
        });
        check("unsafe_role_attributes_block_connector", () -> {
            try {sql(schema,"ALTER ROLE "+PaperWriterConnector.ROLE+" INHERIT");reject(() -> {try(var c=writer()){throw new AssertionError("Unsafe role accepted");}});}
            finally {sql(schema,"ALTER ROLE "+PaperWriterConnector.ROLE+" NOINHERIT");}
        });
        check("money_secret_and_ddl_operations_are_denied", () -> {
            for(String query:List.of("UPDATE paper_portfolio SET current_cash=1", "UPDATE paper_ledger_account SET cash=1",
                    "INSERT INTO paper_ledger_order DEFAULT VALUES", "SELECT * FROM paper_approval_delivery LIMIT 1",
                    "SELECT * FROM paper_approval_key_binding LIMIT 1", "CREATE TEMP TABLE forbidden(id int)",
                    "SET ROLE "+PaperWriterVerification.HELPER))
                PaperRecoveryVerification.denied(() -> {try(var c=writer();var q=c.createStatement()){q.execute(query);}});
        });
        check("concurrent_callbacks_have_one_terminal_receipt", () -> {
            var t=issue(schema,"bridge-race");var cb=callback(p -> quote(),Clock.fixed(T,ZoneOffset.UTC));
            var pool=Executors.newFixedThreadPool(2);
            try {var a=pool.submit(() -> handle(cb,"race-a",t.accept()));var b=pool.submit(() -> handle(cb,"race-b",t.accept()));
                eq(a.get(25,TimeUnit.SECONDS),b.get(25,TimeUnit.SECONDS));
                eq(number(schema,"SELECT count(*) FROM paper_approval_proposal WHERE id='bridge-race' AND receipt IS NOT NULL"),1L);
            } finally {pool.shutdownNow();}
        });
        check("cash_revision_and_orders_unchanged", () -> PaperApprovalVerification.unchanged(schema));
    }
    static void recover(String schema) throws Exception {
        configure(schema);
        check("fresh_process_replays_saved_receipt_without_quote", () -> {
            String token;try(var c=connect(schema);var s=c.createStatement();var r=s.executeQuery("SELECT value FROM bridge_restart_token")){
                if(!r.next())throw new AssertionError("Missing restart fixture"); token=r.getString(1);
            }
            eq(handle(callback(p -> {throw new AssertionError();},Clock.fixed(T.plusSeconds(999),ZoneOffset.UTC)),"restart",token),
                    "PAPER review accepted. Execution remains disabled; no order or reservation created.");
        });
        check("fresh_process_reject_works_with_restricted_login", () -> {
            var t=issue(schema,"bridge-restart-reject");
            eq(handle(callback(p -> {throw new AssertionError();},Clock.fixed(T,ZoneOffset.UTC)),"restart-reject",t.reject()),
                    "PAPER proposal rejected. No trade created.");
        });
        check("restart_cash_revision_and_orders_unchanged", () -> PaperApprovalVerification.unchanged(schema));
    }
    public static void main(String[] args) throws Exception {
        if(args.length!=2||!Set.of("--prepare","--recover").contains(args[0]))throw new IllegalArgumentException("Isolated phase required");
        PaperWriterVerification.schema(args[1]);String schema=args[1];long started=System.nanoTime();
        try {if(args[0].equals("--prepare"))prepare(schema);else recover(schema);}
        finally {if(credential!=null)Files.deleteIfExists(credential);}
        long failed=checks.stream().filter(r -> !Boolean.TRUE.equals(r.get("passed"))).count();var result=new LinkedHashMap<String,Object>();
        result.put("version","PAPER_TELEGRAM_REVIEW_V1");result.put("status",failed==0?"ISOLATED_TELEGRAM_REVIEW_PASSED":"FAILED");
        result.put("phase",args[0]);result.put("schema",schema);result.put("checks",checks);result.put("checkCount",checks.size());
        result.put("failedCount",failed);result.put("elapsedSeconds",(System.nanoTime()-started)/1e9);
        result.put("applicationDatabaseAccessed",false);result.put("applicationWriterActivated",false);result.put("actionExecutionEnabled",false);
        result.put("syntheticDatabaseWritesPerformed",true);result.put("telegramCalls",0);result.put("providerCalls",0);result.put("modelCalls",0);
        if(failed==0){result.put("cashPaise",number(schema,"SELECT cash FROM paper_ledger_account"));
            result.put("reservedCashPaise",number(schema,"SELECT reserved FROM paper_ledger_account"));result.put("ledgerRevision",number(schema,"SELECT revision FROM paper_ledger_account"));
            result.put("orderCount",number(schema,"SELECT count(*) FROM paper_ledger_order"));result.put("fillCount",number(schema,"SELECT count(*) FROM paper_ledger_fill"));}
        System.out.println(PaperPersistenceEngineering.encode(result));if(failed>0)System.exit(2);
    }
}
