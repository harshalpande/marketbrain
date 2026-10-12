package in.marketbrain.paper;

import java.net.URLClassLoader;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.jar.JarFile;

/** Standalone diagnostic, not an endpoint/bean. Runs inside the existing app container.
 * Loads only its bundled JDBC driver; credentials never leave that container.
 */
public final class PaperApplicationRouteProbe {
    static final String SQL = """
        SELECT jsonb_build_object('version','PAPER_APPLICATION_ROUTE_V1',
          'status','READ_ONLY_APPLICATION_ROUTE_OBSERVED','database',current_database(),
          'databaseOid',(SELECT oid::text FROM pg_catalog.pg_database WHERE datname=current_database()),
          'applicationUser',current_user,'sessionUser',session_user,
          'clientAddress',inet_client_addr()::text,'serverAddress',inet_server_addr()::text,
          'serverPort',inet_server_port(),
          'serverStartEpoch',extract(epoch FROM pg_catalog.pg_postmaster_start_time())::text,
          'applicationName',current_setting('application_name'),
          'readOnly',current_setting('transaction_read_only')='on',
          'databaseWritesPerformed',false,'writerLoginAttempted',false,'actionExecutionEnabled',false)
        """;
    static String approvedUrl(String value, String database, String port) {
        if(database==null || !database.matches("[a-z][a-z0-9_]{0,62}") || port==null || !port.matches("[0-9]{1,5}")
                || Integer.parseInt(port)<1 || Integer.parseInt(port)>65535)
            throw new IllegalArgumentException("PROBE_TARGET_INVALID");
        String expected="jdbc:postgresql://host.docker.internal:"+port+"/"+database;
        if(!expected.equals(value)) throw new IllegalArgumentException("PROBE_ROUTE_NOT_APPROVED");
        return expected;
    }
    static Properties properties(String user,String password,String id) {
        if(user==null || !user.matches("[A-Za-z_][A-Za-z0-9_]{0,62}") || password==null || password.isEmpty()
                || id==null || !id.matches("[a-f0-9]{32}")) throw new IllegalArgumentException("PROBE_INPUT_INVALID");
        Properties p=new Properties();p.setProperty("user",user);p.setProperty("password",password);
        p.setProperty("ApplicationName","mb-route-"+id);p.setProperty("connectTimeout","5");
        p.setProperty("loginTimeout","10");p.setProperty("socketTimeout","10");
        p.setProperty("sslmode","disable");p.setProperty("gssEncMode","disable");
        p.setProperty("options","-c default_transaction_read_only=on -c statement_timeout=5000 -c lock_timeout=1000");
        return p;
    }
    static String inspect(Driver driver,String url,Properties p) throws SQLException {
        try(Connection c=driver.connect(url,p)) {
            if(c==null)throw new SQLException("PROBE_DRIVER_REFUSED");
            c.setReadOnly(true);c.setAutoCommit(false);
            try(Statement s=c.createStatement()) {
                s.setQueryTimeout(5);
                try(ResultSet r=s.executeQuery(SQL)) {
                    if(!r.next())throw new SQLException("PROBE_EMPTY_RESULT");
                    String result=r.getString(1);
                    if(result==null || result.length()>8192 || r.next())throw new SQLException("PROBE_RESULT_INVALID");
                    c.rollback();return result;
                }
            }
        } finally {p.clear();}
    }
    public static void main(String[] args) {
        Thread watchdog=new Thread(()->{try{Thread.sleep(45000);System.exit(3);}catch(InterruptedException ignored){Thread.currentThread().interrupt();}},"route-probe-deadline");
        watchdog.setDaemon(true);watchdog.start();
        Path folder=null,driverFile=null;Properties p=null;int exit=0;
        try {
            if(args.length!=3)throw new IllegalArgumentException("PROBE_ARGUMENTS_INVALID");
            String url=approvedUrl(System.getenv("MARKETBRAIN_DB_URL"),args[0],args[1]);
            p=properties(System.getenv("MARKETBRAIN_DB_USERNAME"),System.getenv("MARKETBRAIN_DB_PASSWORD"),args[2]);
            folder=Files.createTempDirectory("mb-route-driver-");folder.toFile().deleteOnExit();
            driverFile=folder.resolve("driver.jar");driverFile.toFile().deleteOnExit();
            try(JarFile app=new JarFile("/app/app.jar")) {
                var matches=app.stream().filter(e->e.getName().matches("BOOT-INF/lib/postgresql-[A-Za-z0-9.-]+\\.jar")).toList();
                if(matches.size()!=1)throw new IllegalArgumentException("PROBE_DRIVER_LAYOUT_UNSUPPORTED");
                try(var input=app.getInputStream(matches.getFirst())) {
                    byte[] bytes=input.readNBytes(16*1024*1024+1);
                    if(bytes.length>16*1024*1024)throw new IllegalArgumentException("PROBE_DRIVER_TOO_LARGE");
                    Files.write(driverFile,bytes,StandardOpenOption.CREATE_NEW);
                }
            }
            try(URLClassLoader loader=new URLClassLoader(new java.net.URL[]{driverFile.toUri().toURL()},ClassLoader.getPlatformClassLoader())) {
                Driver driver=(Driver)loader.loadClass("org.postgresql.Driver").getConstructor().newInstance();
                System.out.println(inspect(driver,url,p));
            }
        } catch(Exception failure) {
            // Neither JDBC messages, raw SQL nor environment values belong in diagnostics.
            String code=failure instanceof IllegalArgumentException && failure.getMessage()!=null && failure.getMessage().matches("PROBE_[A-Z_]+")?failure.getMessage():"PROBE_CONNECTION_OR_QUERY_FAILED";
            System.out.println("{\"version\":\"PAPER_APPLICATION_ROUTE_V1\",\"status\":\"FAILED\",\"failureCode\":\""+code+"\"}");exit=2;
        } finally {
            if(p!=null)p.clear();
            try{if(driverFile!=null)Files.deleteIfExists(driverFile);if(folder!=null)Files.deleteIfExists(folder);}catch(Exception ignored){exit=2;}
        }
        System.exit(exit);
    }
}
