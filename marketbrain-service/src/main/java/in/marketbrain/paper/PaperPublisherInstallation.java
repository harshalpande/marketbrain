package in.marketbrain.paper;

import java.sql.*;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** Explicit administrative installation engine. No startup hook, credentials or login activation. */
public final class PaperPublisherInstallation {
    public static final String HELPER="marketbrain-paper-publisher-helper";
    public enum Mode { REHEARSE_ROLLBACK, INSTALL_DISABLED }
    public record Target(String database,long databaseOid,String schema) {
        public Target {
            if(database==null||!database.matches("[a-z][a-z0-9_]{0,62}")||databaseOid<=0
                    ||schema==null||!schema.matches("[a-z][a-z0-9_]{0,62}"))throw new IllegalArgumentException("Invalid installation target");
        }
    }
    public record Receipt(String status,boolean committed,boolean loginEnabled,boolean applicationActivated){}
    private static final List<String> TABLES=List.of("paper_approval_proposal","paper_approval_token","paper_approval_delivery",
        "paper_approval_key_binding","telegram_binding","paper_portfolio","paper_ledger_account","paper_ledger_command","paper_ledger_position","instrument");
    private static final List<String> FUNCTIONS=List.of("paper_publish_enqueue(text,text,text,text,text,timestamptz)",
        "paper_publish_lock(text)","paper_publish_transition(text,text,text,timestamptz,text)");
    private PaperPublisherInstallation(){}
    static String quoted(String identifier){return "\""+identifier.replace("\"","\"\"")+"\"";}
    /** Own transaction on a dedicated admin connection. Existing roles/functions are never adopted or replaced. */
    public static Receipt run(Connection c,Target target,Mode mode)throws Exception {
        java.util.Objects.requireNonNull(target);java.util.Objects.requireNonNull(mode);
        if(!c.getAutoCommit()||c.isReadOnly())throw new SQLException("PUBLISHER_INSTALL_DEDICATED_CONNECTION_REQUIRED");
        c.setAutoCommit(false);
        try(var s=c.createStatement()) {
            s.setQueryTimeout(15);
            s.execute("SET LOCAL statement_timeout='10s'; SET LOCAL lock_timeout='5s'");
            try(var r=s.executeQuery("SELECT current_database(),d.oid::bigint,current_user=session_user AND r.rolsuper FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()")) {
                if(!r.next()||!target.database().equals(r.getString(1))||target.databaseOid()!=r.getLong(2)||!r.getBoolean(3))
                    throw new SQLException("PUBLISHER_INSTALL_TARGET_OR_ADMIN_MISMATCH");
            }
            s.execute("SELECT pg_catalog.pg_advisory_xact_lock(739241,1)");
            try(var p=c.prepareStatement("SELECT count(*) FROM pg_catalog.pg_roles WHERE rolname IN (?,?)")) {
                p.setQueryTimeout(10);p.setString(1,PaperPaytmReviewPublisher.ROLE);p.setString(2,HELPER);
                try(var r=p.executeQuery()){r.next();if(r.getLong(1)!=0)throw new SQLException("PUBLISHER_INSTALL_ROLE_ALREADY_EXISTS");}
            }
            try(var p=c.prepareStatement("SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=? AND p.proname IN ('paper_publish_enqueue','paper_publish_lock','paper_publish_transition')")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());
                try(var r=p.executeQuery()){r.next();if(r.getLong(1)!=0)throw new SQLException("PUBLISHER_INSTALL_FUNCTION_ALREADY_EXISTS");}
            }
            String schema=quoted(target.schema()),login=quoted(PaperPaytmReviewPublisher.ROLE),helper=quoted(HELPER);
            try(var p=c.prepareStatement("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspname=?) AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace n CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a WHERE n.nspname=? AND a.grantee=0 AND a.privilege_type='CREATE')")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());p.setString(2,target.schema());
                try(var r=p.executeQuery()){if(!r.next()||!r.getBoolean(1))throw new SQLException("PUBLISHER_INSTALL_SCHEMA_UNTRUSTED");}
            }
            // Resolve and lock dependencies before creating any role. No table contents are changed.
            for(String table:TABLES)s.execute("LOCK TABLE "+schema+"."+quoted(table)+" IN ACCESS SHARE MODE");
            s.execute("SET LOCAL search_path=pg_catalog,"+schema);
            for(String role:List.of(login,helper))s.execute("CREATE ROLE "+role+" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS");
            s.execute("GRANT CONNECT ON DATABASE "+quoted(target.database())+" TO "+login);
            s.execute("GRANT USAGE ON SCHEMA "+schema+" TO "+login+","+helper);
            for(String table:TABLES)s.execute("GRANT SELECT ON "+schema+"."+quoted(table)+" TO "+login+","+helper);
            s.execute("GRANT INSERT ON paper_approval_proposal,paper_approval_token,paper_approval_delivery TO "+helper);
            s.execute("GRANT UPDATE(state,attempt_id,attempted_at,message_id) ON paper_approval_delivery TO "+helper);
            s.execute("GRANT UPDATE(id) ON paper_portfolio TO "+helper+"; GRANT UPDATE(portfolio_id) ON paper_ledger_account TO "+helper+"; GRANT UPDATE(binding_key) ON telegram_binding TO "+helper);
            String sql;
            try(var in=PaperPublisherInstallation.class.getResourceAsStream("/paper/approval-publisher-v1.sql")) {
                if(in==null)throw new IllegalStateException("Publisher SQL missing");sql=new String(in.readAllBytes(),StandardCharsets.UTF_8);
            }
            s.execute(sql.replace("__SCHEMA__",schema).replace("__POLICY_JSON__",PaperPersistenceEngineering.encode(PaperReviewTestPolicy.paytmPolicy()).replace("'","''")));
            s.execute("GRANT CREATE ON SCHEMA "+schema+" TO "+helper);
            for(String signature:FUNCTIONS)s.execute("ALTER FUNCTION "+schema+"."+signature+" OWNER TO "+helper+"; GRANT EXECUTE ON FUNCTION "+schema+"."+signature+" TO "+login);
            s.execute("REVOKE CREATE ON SCHEMA "+schema+" FROM "+helper);
            // Existing admin default privileges must not expose these new entrypoints to another role.
            try(var p=c.prepareStatement("SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE n.nspname=? AND p.proname IN ('paper_publish_enqueue','paper_publish_lock','paper_publish_transition') AND a.privilege_type='EXECUTE' AND a.grantee NOT IN (p.proowner,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname=?))")) {
                p.setQueryTimeout(10);p.setString(1,target.schema());p.setString(2,PaperPaytmReviewPublisher.ROLE);
                try(var r=p.executeQuery()){r.next();if(r.getLong(1)!=0)throw new SQLException("PUBLISHER_INSTALL_UNEXPECTED_EXECUTE_GRANT");}
            }
            if(mode==Mode.REHEARSE_ROLLBACK){c.rollback();return new Receipt("PUBLISHER_INSTALL_REHEARSED_ROLLED_BACK",false,false,false);}
            c.commit();return new Receipt("PUBLISHER_INSTALLED_LOGIN_DISABLED",true,false,false);
        } catch(Exception failure){c.rollback();throw failure;}
        finally{c.setAutoCommit(true);}
    }
}
