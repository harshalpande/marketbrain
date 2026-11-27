package in.marketbrain.paper;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.*;
import java.sql.*;
import java.util.*;

/** Local stdin-only credential staging. Never enables login or changes application rows. */
public final class PaperPublisherCredential {
    static void validateVerifier(String value) {
        if(value==null||!value.matches("^SCRAM-SHA-256\\$4096:[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$"))
            throw new IllegalArgumentException("Verifier format");
    }
    record Request(PaperPublisherRehearsal.Request connection,String verifier) {}
    static Request read(InputStream input)throws Exception {
        byte[] bytes=input.readNBytes(16385),base=null;
        try {
            if(bytes.length>16384)throw new IllegalArgumentException("Input bound");
            var mapper=new ObjectMapper();var node=mapper.readTree(bytes);
            if(!(node instanceof ObjectNode n)||!n.has("verifier")||!n.get("verifier").isTextual())throw new IllegalArgumentException("Input fields");
            String verifier=n.remove("verifier").textValue();validateVerifier(verifier);
            base=mapper.writeValueAsBytes(n);
            return new Request(PaperPublisherRehearsal.read(new ByteArrayInputStream(base)),verifier);
        }finally{Arrays.fill(bytes,(byte)0);if(base!=null)Arrays.fill(base,(byte)0);}
    }
    static String phase(Connection c,PaperPublisherInstallation.Target target,String verifier,boolean mutate,boolean commit,Map<String,Object> report)throws Exception {
        validateVerifier(verifier);PaperPublisherInstall.check(c.getAutoCommit());
        c.setReadOnly(!mutate);c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);c.setAutoCommit(false);
        try {
            try(var s=c.createStatement()) {
                s.setQueryTimeout(10);
                try(var r=s.executeQuery("SELECT pg_catalog.pg_try_advisory_xact_lock(1987654321,15)")){PaperPublisherInstall.check(r.next()&&r.getBoolean(1));}
            }
            PaperPublisherInstall.verifyInTransaction(c,target,verifier);
            String current;
            try(var p=c.prepareStatement("SELECT rolpassword,NOT EXISTS(SELECT 1 FROM pg_catalog.pg_stat_activity a WHERE a.usesysid=r.oid) FROM pg_catalog.pg_authid r WHERE rolname='marketbrain-paper-publisher'")) {
                p.setQueryTimeout(10);try(var r=p.executeQuery()){PaperPublisherInstall.check(r.next()&&r.getBoolean(2));current=r.getString(1);PaperPublisherInstall.check(!r.next());}
            }
            PaperPublisherInstall.check(current==null||current.equals(verifier));
            if(mutate&&current==null) {
                try(var s=c.createStatement()){s.setQueryTimeout(10);s.execute("ALTER ROLE \"marketbrain-paper-publisher\" NOLOGIN PASSWORD '"+verifier+"'");}
                current=verifier;
                PaperPublisherInstall.verifyInTransaction(c,target,verifier);
            }
            if(commit){report.put("commitOutcome","UNKNOWN_AFTER_ATTEMPT");c.commit();report.put("commitOutcome","COMMITTED");}
            return current==null?"MISSING":"MATCH";
        }finally{c.rollback();c.setAutoCommit(true);}
    }
    static void execute(Connection c,PaperPublisherInstallation.Target target,String verifier,boolean verifyOnly,Map<String,Object> report)throws Exception {
        String state=phase(c,target,verifier,false,false,report);
        if(state.equals("MISSING")) {
            if(verifyOnly)throw new SQLException("PUBLISHER_CREDENTIAL_MISSING");
            PaperPublisherInstall.check(phase(c,target,verifier,true,false,report).equals("MATCH"));
            PaperPublisherInstall.check(phase(c,target,verifier,false,false,report).equals("MISSING"));report.put("rollbackVerified",true);
            PaperPublisherInstall.check(phase(c,target,verifier,true,true,report).equals("MATCH"));
        } else report.put("commitOutcome","EXISTING_MATCH_NO_CHANGE");
        PaperPublisherInstall.check(phase(c,target,verifier,false,false,report).equals("MATCH"));
        report.put("status","PUBLISHER_CREDENTIAL_VERIFIED_LOGIN_DISABLED");report.put("disabledStateVerified",true);
        report.put("loginEnabled",false);report.put("credentialVerified",true);
    }
    // Read the rules from the same Docker client route used by the administrator.
    // PostgreSQL exposes the parsed disk configuration here. Authentication is a later test.
    static Map<String,Object> reviewAccess(Connection c)throws SQLException {
        String sql="""
            SELECT CASE WHEN family(inet_client_addr())=4 THEN 'IPV4' ELSE 'IPV6' END,
              EXISTS(SELECT FROM pg_catalog.pg_hba_file_rules WHERE error IS NOT NULL),
              EXISTS(SELECT FROM pg_catalog.pg_hba_file_rules WHERE type LIKE 'host%'
                AND database=ARRAY[current_database()::text] AND user_name=ARRAY['marketbrain-paper-publisher']
                AND address=host(inet_client_addr()) AND netmask IN ('255.255.255.255','ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
                AND auth_method='scram-sha-256'),
              EXISTS(SELECT FROM pg_catalog.pg_hba_file_rules WHERE type LIKE 'host%'
                AND 'marketbrain-paper-publisher'=ANY(user_name) AND auth_method='reject')
            """;
        var blockers=new ArrayList<String>();
        try(var s=c.createStatement()){s.setQueryTimeout(10);try(var r=s.executeQuery(sql)){
            if(!r.next())throw new SQLException("HBA_REVIEW_EMPTY");
            if(r.getBoolean(2))blockers.add("HBA_PARSE_ERRORS");
            if(!r.getBoolean(3))blockers.add("EXACT_SOURCE_SCRAM_RULE_ABSENT");
            if(!r.getBoolean(4))blockers.add("PUBLISHER_REJECT_RULE_ABSENT");
            return Map.of("scope",r.getString(1),"installationBlockers",blockers,"status","HBA_RULE_INVENTORY_CAPTURED");
        }}
    }
    public static void main(String[] args)throws Exception {
        var report=new LinkedHashMap<String,Object>();report.put("version","PAPER_PUBLISHER_CREDENTIAL_V1");report.put("status","STOPPED_REVIEW_REQUIRED");
        report.put("commitOutcome","NOT_ATTEMPTED");report.put("actionExecutionEnabled",false);
        Properties props=null;int exit=1;long start=System.nanoTime();
        try {
            if(args.length!=1||!Set.of("--stage-disabled","--verify-only").contains(args[0]))throw new IllegalArgumentException("Explicit mode required");
            var request=read(System.in);props=PaperPublisherRehearsal.properties(request.connection());
            props.setProperty("ApplicationName","marketbrain-publisher-credential");
            try(var c=DriverManager.getConnection(request.connection().url(),props)){
                boolean verifyOnly=args[0].equals("--verify-only");
                execute(c,request.connection().target(),request.verifier(),verifyOnly,report);
                if(verifyOnly)report.putAll(reviewAccess(c));
            }exit=0;
        }catch(Exception e){report.put("failureType",e.getClass().getSimpleName());if(e instanceof SQLException s&&s.getSQLState()!=null&&s.getSQLState().matches("[A-Z0-9]{5}"))report.put("sqlState",s.getSQLState());}
        finally{if(props!=null)props.clear();}
        report.put("elapsedSeconds",(System.nanoTime()-start)/1e9);System.out.println(new ObjectMapper().writeValueAsString(report));System.exit(exit);
    }
}
