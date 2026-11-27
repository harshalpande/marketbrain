package in.marketbrain.paper;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.sql.*;
import java.util.*;

/** Explicit stdin-only operator rehearsal. No commit mode, Spring startup hook or credential storage. */
public final class PaperPublisherRehearsal {
    record Request(String url, String user, String password, PaperPublisherInstallation.Target target) {}
    static Request read(InputStream input) throws Exception {
        byte[] bytes=input.readNBytes(16385);
        try {
            if(bytes.length>16384)throw new IllegalArgumentException("Input bound");
            JsonNode n=new ObjectMapper().readTree(bytes);
            Set<String> fields=new HashSet<>();n.fieldNames().forEachRemaining(fields::add);
            if(!fields.equals(Set.of("url","user","password","database","databaseOid","schema")))throw new IllegalArgumentException("Input fields");
            for(String key:List.of("url","user","password","database","schema"))if(!n.get(key).isTextual())throw new IllegalArgumentException("Input type");
            if(!n.get("databaseOid").isIntegralNumber()||!n.get("databaseOid").canConvertToLong())throw new IllegalArgumentException("OID type");
            String user=n.get("user").textValue(),password=n.get("password").textValue();
            if(!user.matches("[A-Za-z_][A-Za-z0-9_]{0,62}")||password.isBlank()||password.length()>4096||!"public".equals(n.get("schema").textValue()))throw new IllegalArgumentException("Unsupported request");
            return new Request(PaperWriterPreflight.validateUrl(n.get("url").textValue()),user,password,
                new PaperPublisherInstallation.Target(n.get("database").textValue(),n.get("databaseOid").longValue(),"public"));
        } finally {Arrays.fill(bytes,(byte)0);}
    }
    static Properties properties(Request request) {
        Properties p=new Properties();p.setProperty("user",request.user());p.setProperty("password",request.password());
        p.setProperty("connectTimeout","5");p.setProperty("socketTimeout","30");
        p.setProperty("ApplicationName","marketbrain-publisher-rehearsal");
        p.setProperty("options","-c statement_timeout=10000 -c lock_timeout=5000 -c idle_in_transaction_session_timeout=20000");return p;
    }
    @SuppressWarnings("unchecked")
    static void requireCatalog(Map<String,Object> catalog,PaperPublisherInstallation.Target target) throws SQLException {
        Map<String,Object> actual=(Map<String,Object>)catalog.get("target");
        Map<String,Object> session=(Map<String,Object>)catalog.get("session");
        if(!target.database().equals(actual.get("database"))||((Number)actual.get("databaseOid")).longValue()!=target.databaseOid()
            ||!Boolean.TRUE.equals(session.get("superuser"))||!((List<?>)catalog.get("installationBlockers")).isEmpty()
            ||Boolean.TRUE.equals(catalog.get("catalogListBoundReached")))throw new SQLException("PUBLISHER_REHEARSAL_CATALOG_BLOCKED");
    }
    static Map<String,Object> rehearse(Connection c,PaperPublisherInstallation.Target target) throws Exception {
        var before=PaperWriterPreflight.inspect(c,target.schema(),true);requireCatalog(before,target);
        c.setAutoCommit(true);c.setReadOnly(false);c.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
        var receipt=PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK);
        if(receipt.committed()||receipt.loginEnabled()||receipt.applicationActivated())throw new SQLException("Unexpected receipt");
        var after=PaperWriterPreflight.inspect(c,target.schema(),true);requireCatalog(after,target);
        if(!before.equals(after))throw new SQLException("PUBLISHER_REHEARSAL_CATALOG_CHANGED");
        return Map.of("status","PUBLISHER_REHEARSAL_ROLLBACK_VERIFIED","rollbackVerified",true,"committed",false,
            "loginEnabled",false,"applicationWriterActivated",false,"actionExecutionEnabled",false);
    }
    public static void main(String[] args)throws Exception {
        Map<String,Object> report=new LinkedHashMap<>();report.put("version","PAPER_PUBLISHER_REHEARSAL_V1");
        report.put("status","STOPPED_REVIEW_REQUIRED");report.put("rollbackVerified",false);report.put("actionExecutionEnabled",false);
        int exit=1;long start=System.nanoTime();Properties p=null;
        try {
            if(args.length!=0)throw new IllegalArgumentException("No arguments supported");
            Request request=read(System.in);p=properties(request);
            try(Connection c=DriverManager.getConnection(request.url(),p)){report.putAll(rehearse(c,request.target()));}exit=0;
        }catch(Exception e){report.put("status","STOPPED_REVIEW_REQUIRED");report.put("failureType",e.getClass().getSimpleName());if(e instanceof SQLException s&&s.getSQLState()!=null&&s.getSQLState().matches("[A-Z0-9]{5}"))report.put("sqlState",s.getSQLState());}
        finally{if(p!=null)p.clear();}
        report.put("elapsedSeconds",(System.nanoTime()-start)/1e9);
        System.out.println(new ObjectMapper().writeValueAsString(report));System.exit(exit);
    }
}
