package in.marketbrain.paper;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import org.springframework.jdbc.datasource.AbstractDataSource;
import javax.sql.DataSource;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.sql.Connection;
import java.util.*;

/** Network-none disposable container only. No application database, real credentials or Telegram access. */
public final class PaperRuntimeReviewVerification {
    private static final List<Map<String,Object>> checks = new ArrayList<>();
    private static int connectionAttempts;
    @FunctionalInterface interface Check { void run() throws Exception; }
    private static void check(String name, Check body) {
        long start=System.nanoTime(); var row=new LinkedHashMap<String,Object>(); row.put("name",name);
        try { body.run(); row.put("passed",true); }
        catch(Exception|AssertionError failure){ row.put("passed",false);row.put("failureType",failure.getClass().getSimpleName()); }
        row.put("elapsedMillis",(System.nanoTime()-start)/1e6);checks.add(row);
    }
    private static void require(boolean ok) { if(!ok)throw new AssertionError("Runtime fixture assertion failed"); }
    private static void refuses(Check body) throws Exception {
        try {body.run();}catch(Exception expected){return;}throw new AssertionError("Expected refusal");
    }
    static Map<String,Object> properties() {
        var p=new LinkedHashMap<String,Object>(); String prefix="marketbrain.paper.review.";
        p.put(prefix+"enabled","true");p.put(prefix+"credential-mode","PROCESS_MEMORY");
        p.put(prefix+"activation","REVIEW_ONLY");p.put(prefix+"transport","PRIVATE_SAME_MACHINE");
        p.put(prefix+"host","127.0.0.1");p.put(prefix+"port","5432");p.put(prefix+"database","paper_fixture");
        p.put(prefix+"database-oid","1");p.put(prefix+"policy-id",PaperReviewTestPolicy.ID);
        p.put(prefix+"max-quote-age-millis","15000");p.put(prefix+"max-slippage-bps","50");
        p.put(prefix+"max-quantity","1");p.put(prefix+"max-order-notional-paise","500000");
        p.put(prefix+"max-approvals","2");p.put(prefix+"max-fills","1");p.put(prefix+"max-proposal-lifetime-seconds","100");
        return p;
    }
    static MarketBrainProperties app() {
        return new MarketBrainProperties("PAPER",null,null,null,null,
                new MarketBrainProperties.Upstox("https://api.upstox.com","unused",true,"synthetic-never-sent"),
                new MarketBrainProperties.Telegram(true,"synthetic-never-sent","SYNTHETIC",20,1000,false));
    }
    static AnnotationConfigApplicationContext context() {
        var c=new AnnotationConfigApplicationContext();
        c.getEnvironment().getPropertySources().addFirst(new MapPropertySource("fixture",properties()));
        c.registerBean(MarketBrainProperties.class,PaperRuntimeReviewVerification::app);
        c.registerBean(DataSource.class,()->new AbstractDataSource(){
            @Override public Connection getConnection(){connectionAttempts++;throw new AssertionError("No database in runtime custody fixture");}
            @Override public Connection getConnection(String u,String p){return getConnection();}
        });
        c.register(PaperTelegramReviewConfiguration.class);c.refresh();return c;
    }
    static void suite() throws Exception {
        Path directory=PaperRuntimeControl.DIRECTORY;Path socket=PaperRuntimeControl.SOCKET;
        byte[] a="ab".repeat(32).getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        byte[] b="cd".repeat(32).getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        try(var c=context()){
            var credential=c.getBean(PaperRuntimeCredential.class);
            check("spring_memory_mode_starts_locked_without_database",()->require(!credential.ready()&&connectionAttempts==0));
            check("approved_100_second_policy_registered",()->PaperReviewTestPolicy.requireExact(c.getBean(PaperTelegramReviewConfiguration.Settings.class).policy()));
            check("no_publisher_or_execution_bean",()->require(c.getBeansOfType(PaperApprovalDelivery.class).isEmpty()&&c.getBeansOfType(PaperLedgerStore.class).isEmpty()));
            check("locked_callback_never_dials",()->{
                try {
                    c.getBean(PaperApprovalCallback.class).handle("locked",1,1,"private","mbp:"+"a".repeat(43));
                    throw new AssertionError("Locked callback must refuse before database access");
                } catch (PaperRuntimeCredential.Locked expected) { /* Other exceptions must fail this check. */ }
                require(connectionAttempts==0);
            });
            check("unix_socket_has_private_permissions",()->require(Files.getPosixFilePermissions(socket).equals(PosixFilePermissions.fromString("rw-------"))));
            check("status_starts_locked",()->require(PaperRuntimeControl.request(socket,"STATUS",null).equals("LOCKED")));
            check("stdin_frame_unlocks_process_secret",()->require(PaperRuntimeControl.request(socket,"UNLOCK",a).equals("UNLOCKED")&&Arrays.equals(credential.read(),"ab".repeat(32).toCharArray())));
            check("identical_unlock_replay_is_safe",()->require(PaperRuntimeControl.request(socket,"UNLOCK",a).equals("UNLOCKED")));
            check("different_secret_cannot_overwrite",()->require(PaperRuntimeControl.request(socket,"UNLOCK",b).equals("REFUSED")&&Arrays.equals(credential.read(),"ab".repeat(32).toCharArray())));
            check("malformed_secret_refused",()->require(PaperRuntimeControl.request(socket,"UNLOCK",new byte[64]).equals("REFUSED")));
            check("only_socket_metadata_on_filesystem",()->{try(var files=Files.list(directory)){require(files.toList().equals(List.of(socket)));}});
            check("explicit_lock_removes_ready_secret",()->{require(PaperRuntimeControl.request(socket,"LOCK",null).equals("LOCKED"));refuses(credential::read);});
            check("unlock_after_lock_allowed",()->require(PaperRuntimeControl.request(socket,"UNLOCK",b).equals("UNLOCKED")));
        }finally{Arrays.fill(a,(byte)0);Arrays.fill(b,(byte)0);}
        check("shutdown_removes_owned_socket",()->require(!Files.exists(socket,LinkOption.NOFOLLOW_LINKS)));
        try(var restart=context()){
            check("fresh_spring_context_requires_new_unlock",()->require(!restart.getBean(PaperRuntimeCredential.class).ready()
                    &&PaperRuntimeControl.request(socket,"STATUS",null).equals("LOCKED")));
        }
        check("stale_socket_path_never_overwritten",()->{
            Files.createFile(socket);
            try(var c=new PaperRuntimeCredential()){
                refuses(()->new PaperRuntimeControlServer(c,directory));require(Files.isRegularFile(socket));
            }finally{Files.delete(socket);}
        });
        check("broad_directory_permissions_refused",()->{
            Files.setPosixFilePermissions(directory,PosixFilePermissions.fromString("rwxr-xr-x"));
            try{refuses(()->PaperRuntimeControlServer.requirePrivateDirectory(directory));}
            finally{Files.setPosixFilePermissions(directory,PosixFilePermissions.fromString("rwx------"));}
        });
        check("no_database_attempts_across_suite",()->require(connectionAttempts==0));
    }
    public static void main(String[] args) throws Exception {
        if(args.length!=1||!args[0].matches("[a-f0-9]{32}"))throw new IllegalArgumentException("Fixture id required");
        // Fail before tests if this is not the explicitly disposable tmpfs fixture.
        if(!Files.getFileStore(PaperRuntimeControl.DIRECTORY).type().equals("tmpfs"))throw new IllegalArgumentException("Fixture tmpfs required");
        suite();
        var receipt=new LinkedHashMap<String,Object>();receipt.put("version","PAPER_RUNTIME_FIXTURE_V1");receipt.put("runId",args[0]);
        receipt.put("bootId",UUID.randomUUID().toString());
        receipt.put("checks",checks);receipt.put("checkCount",checks.size());
        long failed=checks.stream().filter(r->!Boolean.TRUE.equals(r.get("passed"))).count();
        receipt.put("failedCount",failed);receipt.put("status",failed==0?"RUNTIME_FIXTURE_READY_LOCKED":"FAILED");
        receipt.put("applicationDatabaseAccessed",false);receipt.put("realCredentialUsed",false);receipt.put("realTelegramVerified",false);receipt.put("actionExecutionEnabled",false);
        if(failed!=0){System.out.println("PAPER_RUNTIME_REPORT="+PaperPersistenceEngineering.encode(receipt));System.exit(1);}
        var context=context();
        Runtime.getRuntime().addShutdownHook(new Thread(context::close));
        System.out.println("PAPER_RUNTIME_REPORT="+PaperPersistenceEngineering.encode(receipt));
        new java.util.concurrent.CountDownLatch(1).await();
    }
}
