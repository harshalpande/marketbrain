package in.marketbrain.paper;

import java.io.InputStream;
import java.lang.reflect.Proxy;
import java.net.URLClassLoader;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.*;
import java.util.*;
import java.util.jar.JarFile;

/** Standalone, bounded diagnostic. Not a Spring component. No approval or money operations.
 * Loads the connector and JDBC driver from the RUNNING application's jar; reads a secret only on stdin.
 */
public final class PaperWriterAuthenticationProbe {
    static final String ROLE = "marketbrain_paper_review_writer";
    static final String PREFIX = "in.marketbrain.paper.PaperWriterConnector";
    static char[] password(InputStream input) throws Exception {
        byte[] bytes = input.readNBytes(65);
        try {
            if (bytes.length != 64) throw new IllegalArgumentException("AUTH_SECRET_FORMAT");
            char[] value = new char[64];
            for (int i=0;i<64;i++) {
                if (!((bytes[i]>='0' && bytes[i]<='9') || (bytes[i]>='a' && bytes[i]<='f'))) {
                    Arrays.fill(value, '\0'); throw new IllegalArgumentException("AUTH_SECRET_FORMAT");
                }
                value[i]=(char)bytes[i];
            }
            return value;
        } finally { Arrays.fill(bytes,(byte)0); }
    }
    static Properties properties(char[] secret, String id) {
        Properties p=new Properties();p.setProperty("user",ROLE);p.setProperty("password",new String(secret));
        p.setProperty("ApplicationName","mb-auth-"+id);p.setProperty("sslmode","disable");p.setProperty("gssEncMode","disable");
        p.setProperty("connectTimeout","5");p.setProperty("loginTimeout","5");p.setProperty("socketTimeout","5");
        p.setProperty("options","-c default_transaction_read_only=on -c statement_timeout=5000 -c lock_timeout=1000");return p;
    }
    static void denied(Driver driver,String url,Properties properties,String expected) throws Exception {
        try {
            try(Connection c=driver.connect(url,properties)) {
                // A null connection is not authentication rejection; an unexpected successful connection is closed.
                throw new IllegalArgumentException("AUTH_EXPECTED_DENIAL_MISSING");
            } catch(SQLException e) { if(!expected.equals(e.getSQLState()))throw new IllegalArgumentException("AUTH_DENIAL_STATE_MISMATCH"); }
        } finally { properties.clear(); }
    }
    static String target(String configured,String database,String port,String oid,String id,String epoch) {
        if(!"marketbrain".equals(database) || !"5432".equals(port) || !oid.matches("[1-9][0-9]{0,9}")
                || !id.matches("[a-f0-9]{32}") || !epoch.matches("[0-9]{1,12}\\.[0-9]{1,6}"))
            throw new IllegalArgumentException("AUTH_TARGET_INVALID");
        String expected="jdbc:postgresql://host.docker.internal:"+port+"/"+database;
        if(!expected.equals(configured))throw new IllegalArgumentException("AUTH_ROUTE_CHANGED");return expected;
    }
    static Object configuredConnector(ClassLoader loader,String db,int port,long oid,char[] secret) throws Exception {
        Class<?> transport=loader.loadClass(PREFIX+"$Transport"), target=loader.loadClass(PREFIX+"$Target"), source=loader.loadClass(PREFIX+"$SecretSource");
        Object mode=transport.getField("PRIVATE_SAME_MACHINE").get(null);
        Object t=target.getConstructor(String.class,int.class,String.class,long.class,transport,Path.class)
                .newInstance("host.docker.internal",port,db,oid,mode,null);
        Object s=Proxy.newProxyInstance(loader,new Class<?>[]{source},(proxy,method,args)->{
            if(method.getName().equals("read"))return secret.clone();
            throw new IllegalArgumentException("AUTH_UNEXPECTED_SECRET_METHOD");
        });
        return loader.loadClass(PREFIX).getConstructor(target,source,boolean.class).newInstance(t,s,true);
    }
    static void inspect(Connection c,String epoch) throws Exception {
        try(c) {
            c.setReadOnly(true);c.setAutoCommit(false);
            try(Statement s=c.createStatement()) {
                s.setQueryTimeout(5);
                try(ResultSet r=s.executeQuery("SELECT host(inet_client_addr()),host(inet_server_addr()),inet_server_port(),extract(epoch FROM pg_postmaster_start_time())::text,current_setting('transaction_read_only')")) {
                    if(!r.next() || !"127.0.0.1".equals(r.getString(1)) || !"127.0.0.1".equals(r.getString(2))
                            || r.getInt(3)!=5432 || !epoch.equals(r.getString(4)) || !"on".equals(r.getString(5)) || r.next())
                        throw new IllegalArgumentException("AUTH_ROUTE_IDENTITY_MISMATCH");
                }
                // Zero-row SELECT proves real permission denial, not a read-only-transaction DML error.
                for(String table:List.of("paper_approval_delivery","paper_approval_key_binding","paper_ledger_order","paper_ledger_fill")) {
                    Savepoint point=c.setSavepoint();boolean rejected=false;
                    try(ResultSet ignored=s.executeQuery("SELECT * FROM public."+table+" WHERE false")) { /* no rows requested */ }
                    catch(SQLException failure) { if(!"42501".equals(failure.getSQLState()))throw new IllegalArgumentException("AUTH_READ_DENIAL_STATE");rejected=true; }
                    finally { c.rollback(point);c.releaseSavepoint(point); }
                    if(!rejected)throw new IllegalArgumentException("AUTH_FORBIDDEN_READ_ALLOWED");
                }
            } finally { c.rollback(); }
        }
    }
    static String hash(byte[] bytes) throws Exception {return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    public static void main(String[] args) {
        Thread watchdog=new Thread(()->{try{Thread.sleep(45000);System.exit(3);}catch(InterruptedException e){Thread.currentThread().interrupt();}},"writer-auth-deadline");
        watchdog.setDaemon(true);watchdog.start();
        char[] secret=null,wrong=null;Path folder=null,driverFile=null;int exit=0;String result;
        try {
            if(args.length!=6 || !Set.of("Active","Disabled").contains(args[0]))throw new IllegalArgumentException("AUTH_ARGUMENTS_INVALID");
            String url=target(System.getenv("MARKETBRAIN_DB_URL"),args[1],args[2],args[3],args[4],args[5]);
            secret=password(System.in);String connectorHash,driverHash;
            folder=Files.createTempDirectory("mb-auth-driver-");folder.toFile().deleteOnExit();driverFile=folder.resolve("driver.jar");driverFile.toFile().deleteOnExit();
            try(JarFile app=new JarFile("/app/app.jar")) {
                var drivers=app.stream().filter(e->e.getName().matches("BOOT-INF/lib/postgresql-[A-Za-z0-9.-]+\\.jar")).toList();
                var entry=app.getJarEntry("BOOT-INF/classes/"+PREFIX.replace('.','/')+".class");
                if(drivers.size()!=1 || entry==null)throw new IllegalArgumentException("AUTH_APPLICATION_LAYOUT_UNSUPPORTED");
                try(var in=app.getInputStream(entry)){byte[] bytes=in.readNBytes(1024*1024+1);if(bytes.length>1024*1024)throw new IllegalArgumentException("AUTH_CONNECTOR_SIZE");connectorHash=hash(bytes);}
                try(var in=app.getInputStream(drivers.getFirst())){byte[] bytes=in.readNBytes(16*1024*1024+1);if(bytes.length>16*1024*1024)throw new IllegalArgumentException("AUTH_DRIVER_SIZE");driverHash=hash(bytes);Files.write(driverFile,bytes,StandardOpenOption.CREATE_NEW);}
            }
            try(URLClassLoader loader=new URLClassLoader(new java.net.URL[]{new java.net.URI("jar:file:/app/app.jar!/BOOT-INF/classes/").toURL(),driverFile.toUri().toURL()},ClassLoader.getPlatformClassLoader())) {
                Driver driver=(Driver)Class.forName("org.postgresql.Driver",true,loader).getConstructor().newInstance();
                // Check the deployed connector's full construction/linkage before the runner opens any LOGIN window.
                Object configured=configuredConnector(loader,args[1],Integer.parseInt(args[2]),Long.parseLong(args[3]),secret);
                if(args[0].equals("Disabled"))denied(driver,url,properties(secret,args[4]),"28000");
                else {
                    inspect((Connection)configured.getClass().getMethod("open").invoke(configured),args[5]);
                    wrong=secret.clone();wrong[0]=wrong[0]=='0'?'1':'0';
                    denied(driver,url,properties(wrong,args[4]),"28P01");
                    denied(driver,"jdbc:postgresql://host.docker.internal:5432/postgres",properties(secret,args[4]),"28000");
                }
            }
            result="{\"version\":\"PAPER_WRITER_AUTH_PROBE_V1\",\"phase\":\""+args[0]+"\",\"status\":\"PASSED\",\"runId\":\""+args[4]+"\",\"connectorSha256\":\""+connectorHash+"\",\"driverSha256\":\""+driverHash+"\",\"accountRowsWritten\":false,\"applicationWriterActivated\":false,\"actionExecutionEnabled\":false}";
        } catch(Exception failure) {
            String code=failure instanceof IllegalArgumentException && failure.getMessage()!=null && failure.getMessage().matches("AUTH_[A-Z_]+")?failure.getMessage():"AUTH_CONNECTION_OR_QUERY_FAILED";
            result="{\"version\":\"PAPER_WRITER_AUTH_PROBE_V1\",\"status\":\"FAILED\",\"failureCode\":\""+code+"\"}";exit=2;
        } finally {
            if(secret!=null)Arrays.fill(secret,'\0');if(wrong!=null)Arrays.fill(wrong,'\0');
            try{if(driverFile!=null)Files.deleteIfExists(driverFile);if(folder!=null)Files.deleteIfExists(folder);}catch(Exception ignored){exit=2;}
        }
        System.out.println(result);System.exit(exit);
    }
}
