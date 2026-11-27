package in.marketbrain.paper;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.Pattern;

/** Local administrator operator only. Installation leaves roles NOLOGIN and without passwords. */
public final class PaperPublisherInstall {
    static final List<String> SIGNATURES=List.of("paper_publish_enqueue(text,text,text,text,text,timestamptz)","paper_publish_lock(text)","paper_publish_transition(text,text,text,timestamptz,text)");
    static Map<String,String> expectedBodies(String schema)throws Exception {
        String sql;
        try(var in=PaperPublisherInstall.class.getResourceAsStream("/paper/approval-publisher-v1.sql")) {
            if(in==null)throw new IllegalStateException("SQL missing");sql=new String(in.readAllBytes(),StandardCharsets.UTF_8);
        }
        sql=sql.replace("__SCHEMA__",PaperPublisherInstallation.quoted(schema)).replace("__POLICY_JSON__",PaperPersistenceEngineering.encode(PaperReviewTestPolicy.paytmPolicy()).replace("'","''"));
        var m=Pattern.compile("CREATE FUNCTION [^\\n]*?\\.(paper_publish_[a-z]+)\\(.*?AS \\$\\$(.*?)\\$\\$;",Pattern.DOTALL).matcher(sql);
        Map<String,String> bodies=new HashMap<>();while(m.find())bodies.put(m.group(1),m.group(2).replace("\r\n","\n"));
        if(bodies.size()!=3)throw new IllegalStateException("SQL body count");return bodies;
    }
    static void check(boolean valid)throws SQLException{if(!valid)throw new SQLException("PUBLISHER_DISABLED_STATE_NOT_VERIFIED");}
    static void verify(Connection c,PaperPublisherInstallation.Target target)throws Exception {
        check(c.getAutoCommit());c.setReadOnly(true);c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);c.setAutoCommit(false);
        try(var s=c.createStatement()) {
            s.setQueryTimeout(10);
            try(var r=s.executeQuery("SELECT current_database(),d.oid::bigint,current_user=session_user AND r.rolsuper FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()")) {
                check(r.next()&&target.database().equals(r.getString(1))&&target.databaseOid()==r.getLong(2)&&r.getBoolean(3));
            }
            try(var r=s.executeQuery("SELECT count(*),coalesce(bool_and(NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolinherit AND NOT rolreplication AND NOT rolbypassrls AND rolpassword IS NULL),false) FROM pg_catalog.pg_authid WHERE rolname IN ('marketbrain-paper-publisher','marketbrain-paper-publisher-helper')")) {
                check(r.next()&&r.getInt(1)==2&&r.getBoolean(2));
            }
            try(var r=s.executeQuery("SELECT count(*) FROM pg_catalog.pg_auth_members m JOIN pg_catalog.pg_roles r ON r.oid=m.roleid OR r.oid=m.member WHERE r.rolname IN ('marketbrain-paper-publisher','marketbrain-paper-publisher-helper')")) {check(r.next()&&r.getInt(1)==0);}
            try(var p=c.prepareStatement("SELECT NOT pg_catalog.has_schema_privilege('public',n.oid,'CREATE') AND NOT pg_catalog.has_schema_privilege('marketbrain-paper-publisher',n.oid,'CREATE') AND NOT pg_catalog.has_schema_privilege('marketbrain-paper-publisher-helper',n.oid,'CREATE') FROM pg_catalog.pg_namespace n WHERE n.nspname=?")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());try(var r=p.executeQuery()){check(r.next()&&r.getBoolean(1));}
            }
            try(var p=c.prepareStatement("SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=? AND p.proname IN ('paper_publish_enqueue','paper_publish_lock','paper_publish_transition')")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());try(var r=p.executeQuery()){check(r.next()&&r.getInt(1)==3);}
            }
            var bodies=expectedBodies(target.schema());
            String sql="SELECT p.proname,p.prosrc,p.prosecdef,r.rolname,p.proconfig,l.lanname,p.prorettype::int,"
                +"NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE a.privilege_type='EXECUTE' AND a.grantee NOT IN(p.proowner,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='marketbrain-paper-publisher'))),"
                +"pg_catalog.has_function_privilege('marketbrain-paper-publisher',p.oid,'EXECUTE') FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=pg_catalog.to_regprocedure(?)";
            for(String signature:SIGNATURES)try(var p=c.prepareStatement(sql)) {
                p.setQueryTimeout(10);p.setString(1,PaperPublisherInstallation.quoted(target.schema())+"."+signature);
                try(var r=p.executeQuery()) {
                    check(r.next());String name=r.getString(1);var config=r.getArray(5);
                    try {
                        Object[] settings=config==null?new Object[0]:(Object[])config.getArray();
                        check(bodies.containsKey(name)&&bodies.get(name).equals(r.getString(2).replace("\r\n","\n"))&&r.getBoolean(3)
                            &&PaperPublisherInstallation.HELPER.equals(r.getString(4))&&settings.length==1
                            &&("search_path=pg_catalog,"+target.schema()+",pg_temp").equals(settings[0].toString().replace(" ","").replace("\"",""))
                            &&"plpgsql".equals(r.getString(6))&&r.getInt(7)==(name.equals("paper_publish_enqueue")?25:16)&&r.getBoolean(8)&&r.getBoolean(9));
                    }finally{if(config!=null)config.free();}
                    check(!r.next());
                }
            }
            // Publisher must not bypass its function entrypoints using table or column write grants.
            try(var p=c.prepareStatement("SELECT count(*),coalesce(bool_or(pg_catalog.has_table_privilege('marketbrain-paper-publisher',c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR pg_catalog.has_any_column_privilege('marketbrain-paper-publisher',c.oid,'INSERT,UPDATE,REFERENCES')),false) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=? AND c.relkind IN ('r','p','v','m','f')")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());try(var r=p.executeQuery()){check(r.next()&&r.getInt(1)>=12&&r.getInt(1)<=512&&!r.getBoolean(2));}
            }
        }finally{c.rollback();}
    }
    static void execute(Connection c,PaperPublisherInstallation.Target target,boolean verifyOnly,Map<String,Object> report)throws Exception {
        if(!verifyOnly) {
            PaperPublisherRehearsal.rehearse(c,target);
            c.setAutoCommit(true);c.setReadOnly(false);c.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
            report.put("commitOutcome","UNKNOWN_AFTER_ATTEMPT");
            var receipt=PaperPublisherInstallation.run(c,target,PaperPublisherInstallation.Mode.INSTALL_DISABLED);
            check(receipt.committed()&&!receipt.loginEnabled()&&!receipt.applicationActivated());report.put("commitOutcome","COMMITTED");
        }
        verify(c,target);report.put("disabledStateVerified",true);report.put("loginEnabled",false);report.put("actionExecutionEnabled",false);
        report.put("status",verifyOnly?"PUBLISHER_DISABLED_STATE_VERIFIED":"PUBLISHER_INSTALLED_DISABLED_VERIFIED");
    }
    public static void main(String[] args)throws Exception {
        var report=new LinkedHashMap<String,Object>();report.put("version","PAPER_PUBLISHER_INSTALL_V1");report.put("status","STOPPED_REVIEW_REQUIRED");
        report.put("commitOutcome","NOT_ATTEMPTED");report.put("disabledStateVerified",false);report.put("actionExecutionEnabled",false);
        Properties props=null;int exit=1;long start=System.nanoTime();
        try {
            if(args.length!=1||!Set.of("--install-disabled","--verify-only").contains(args[0]))throw new IllegalArgumentException("Explicit mode required");
            var request=PaperPublisherRehearsal.read(System.in);props=PaperPublisherRehearsal.properties(request);
            try(var c=DriverManager.getConnection(request.url(),props)){execute(c,request.target(),args[0].equals("--verify-only"),report);}exit=0;
        }catch(Exception e){report.put("status","STOPPED_REVIEW_REQUIRED");report.put("failureType",e.getClass().getSimpleName());if(e instanceof SQLException s&&s.getSQLState()!=null&&s.getSQLState().matches("[A-Z0-9]{5}"))report.put("sqlState",s.getSQLState());}
        finally{if(props!=null)props.clear();}
        report.put("elapsedSeconds",(System.nanoTime()-start)/1e9);System.out.println(new ObjectMapper().writeValueAsString(report));System.exit(exit);
    }
}
