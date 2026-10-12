package in.marketbrain.paper;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.*;
import java.time.Instant;
import java.util.*;

/** Standalone catalog inspection, not a Spring bean, installer, health probe or approval writer. */
public final class PaperWriterPreflight {
    static final String VERSION = "PAPER_WRITER_PREFLIGHT_V1";
    static final List<String> TABLES = List.of("paper_approval_proposal", "paper_approval_token",
            "telegram_binding", "paper_portfolio", "paper_ledger_account", "paper_ledger_command",
            "paper_ledger_position", "instrument", "paper_approval_delivery", "paper_approval_key_binding",
            "paper_ledger_order", "paper_ledger_fill");
    static final String SESSION = """
        SELECT current_setting('transaction_read_only') = 'on' AS "readOnly",
               current_setting('transaction_isolation') = 'repeatable read' AS "repeatableRead",
               current_setting('server_version_num')::integer AS "serverVersionNumber",
               current_schema() AS "resolvedSchema",
               current_user = session_user AS "unchangedSessionIdentity",
               r.rolsuper AS "superuser", r.rolcreaterole AS "createRole",
               pg_catalog.has_database_privilege('public', current_database(), 'CREATE') AS "publicDatabaseCreate",
               pg_catalog.has_database_privilege('public', current_database(), 'TEMP') AS "publicDatabaseTemp"
        FROM pg_catalog.pg_roles r WHERE r.rolname = current_user
        """;
    static final String SCHEMA = """
        SELECT n.nspname AS "schemaName",
               pg_catalog.has_schema_privilege(n.oid, 'CREATE') AS "currentRoleCreate",
               pg_catalog.pg_has_role(n.nspowner, 'USAGE') AS "currentRoleOwnerMembership",
               pg_catalog.has_schema_privilege('public', n.oid, 'CREATE') AS "publicCreate"
        FROM pg_catalog.pg_namespace n WHERE n.nspname = ?
        """;
    static final String TABLE = """
        SELECT c.relname AS "tableName", c.relkind::text AS "kind",
               c.relrowsecurity AS "rowSecurity", c.relforcerowsecurity AS "forceRowSecurity",
               pg_catalog.pg_has_role(c.relowner, 'USAGE') AS "currentRoleOwnerMembership",
               pg_catalog.has_table_privilege(c.oid, 'SELECT') AS "currentRoleSelect",
               pg_catalog.has_any_column_privilege('public', c.oid, 'SELECT') AS "publicSelect",
               (pg_catalog.has_any_column_privilege('public', c.oid, 'INSERT') OR
                pg_catalog.has_any_column_privilege('public', c.oid, 'UPDATE') OR
                pg_catalog.has_table_privilege('public', c.oid, 'DELETE,TRUNCATE,TRIGGER')) AS "publicWrite"
        FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = ? AND c.relname = ?
        """;
    static final String COLLISIONS = """
        SELECT r.rolname AS "roleName", r.rolcanlogin AS "login", r.rolsuper AS "superuser",
               r.rolcreaterole AS "createRole", r.rolcreatedb AS "createDatabase",
               r.rolreplication AS "replication", r.rolbypassrls AS "bypassRls"
        FROM pg_catalog.pg_roles r
        WHERE r.rolname IN ('marketbrain_paper_review_writer', 'marketbrain_paper_review_helper')
        ORDER BY r.rolname LIMIT 3
        """;
    static final String FUNCTIONS = """
        SELECT p.proname AS "functionName", p.prosecdef AS "securityDefiner",
               pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE') AS "publicExecute"
        FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = ? AND p.proname IN ('paper_review_lock', 'paper_review_record')
        ORDER BY p.proname, p.oid LIMIT 21
        """;
    static final String PUBLIC_SCHEMAS = """
        SELECT n.nspname AS "schemaName" FROM pg_catalog.pg_namespace n
        WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema'
          AND pg_catalog.has_schema_privilege('public', n.oid, 'CREATE')
        ORDER BY n.nspname LIMIT 21
        """;
    static final String PUBLIC_DEFINERS = """
        SELECT n.nspname AS "schemaName", p.proname AS "functionName"
        FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema' AND p.prosecdef
          AND pg_catalog.has_schema_privilege('public', n.oid, 'USAGE')
          AND pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE')
        ORDER BY n.nspname, p.proname, p.oid LIMIT 21
        """;

    static List<Map<String,Object>> query(Connection c, String sql, String... args) throws SQLException {
        try (var q = c.prepareStatement(sql)) {
            q.setQueryTimeout(5);
            q.setMaxRows(21);
            for (int i=0; i<args.length; i++) q.setString(i+1, args[i]);
            try (var rs = q.executeQuery()) {
                List<Map<String,Object>> rows = new ArrayList<>();
                var metadata = rs.getMetaData();
                while (rs.next()) {
                    if (rows.size() >= 21) throw new SQLException("Catalog bound exceeded");
                    Map<String,Object> row = new LinkedHashMap<>();
                    for (int i=1; i<=metadata.getColumnCount(); i++) row.put(metadata.getColumnLabel(i), rs.getObject(i));
                    rows.add(row);
                }
                return rows;
            }
        }
    }
    static Map<String,Object> one(List<Map<String,Object>> rows) throws SQLException {
        if (rows.size()!=1) throw new SQLException("Expected one catalog row");
        return rows.getFirst();
    }
    static boolean yes(Map<String,Object> row, String key) { return Boolean.TRUE.equals(row.get(key)); }

    static Map<String,Object> inspect(Connection c, String schema) throws SQLException {
        validateSchema(schema);
        c.setReadOnly(true);
        c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
        c.setAutoCommit(false);
        try {
            Map<String,Object> session = one(query(c, SESSION));
            if (!yes(session,"readOnly") || !yes(session,"repeatableRead") || !yes(session,"unchangedSessionIdentity"))
                throw new SQLException("Read-only session guard failed");
            Map<String,Object> namespace = one(query(c, SCHEMA, schema));
            List<Map<String,Object>> tables = new ArrayList<>();
            List<String> blockers = new ArrayList<>();
            if (!schema.equals(session.get("resolvedSchema"))) blockers.add("CONFIGURED_SCHEMA_DIFFERS_FROM_SEARCH_PATH");
            if (!yes(session,"superuser") && !yes(session,"createRole")) blockers.add("ROLE_PROVISIONING_REQUIRES_AUTHORIZED_ADMIN");
            if (!yes(namespace,"currentRoleCreate") || !yes(namespace,"currentRoleOwnerMembership")) blockers.add("SCHEMA_GRANT_AUTHORITY_REQUIRES_REVIEW");
            if (yes(session,"publicDatabaseCreate")) blockers.add("PUBLIC_DATABASE_CREATE_REQUIRES_IMPACT_REVIEW");
            if (yes(session,"publicDatabaseTemp")) blockers.add("PUBLIC_TEMP_REQUIRES_IMPACT_REVIEW");
            for (String name : TABLES) {
                var rows = query(c, TABLE, schema, name);
                Map<String,Object> row = rows.isEmpty() ? new LinkedHashMap<>(Map.of("tableName",name,"present",false)) : new LinkedHashMap<>(one(rows));
                row.putIfAbsent("present",true);
                tables.add(row);
                if (!yes(row,"present")) { blockers.add("MISSING_TABLE:"+name); continue; }
                if (!"r".equals(row.get("kind"))) blockers.add("UNREVIEWED_RELATION_KIND:"+name);
                if (!yes(row,"currentRoleOwnerMembership") || !yes(row,"currentRoleSelect")) blockers.add("TABLE_AUTHORITY_REQUIRES_REVIEW:"+name);
                if (yes(row,"rowSecurity") || yes(row,"forceRowSecurity")) blockers.add("ROW_SECURITY_REQUIRES_REVIEW:"+name);
                if (yes(row,"publicWrite") || yes(row,"publicSelect")) blockers.add("PUBLIC_TABLE_ACCESS_REQUIRES_IMPACT_REVIEW:"+name);
            }
            var roles = query(c, COLLISIONS);
            var functions = query(c, FUNCTIONS, schema);
            var schemas = query(c, PUBLIC_SCHEMAS);
            var definers = query(c, PUBLIC_DEFINERS);
            if (!roles.isEmpty()) blockers.add("PROPOSED_ROLE_NAME_COLLISION_DO_NOT_ADOPT");
            if (!functions.isEmpty()) blockers.add("EXISTING_WRITER_FUNCTIONS_DO_NOT_REPLACE");
            if (!schemas.isEmpty()) blockers.add("PUBLIC_SCHEMA_CREATE_REQUIRES_IMPACT_REVIEW");
            if (!definers.isEmpty()) blockers.add("PUBLIC_SECURITY_DEFINER_REQUIRES_IMPACT_REVIEW");
            boolean bounded = functions.size()>=21 || schemas.size()>=21 || definers.size()>=21;
            if (bounded) blockers.add("CATALOG_LIST_BOUND_REACHED_REVIEW_INCOMPLETE");
            Map<String,Object> result = new LinkedHashMap<>();
            result.put("version",VERSION);
            result.put("status","CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED");
            result.put("session",session); result.put("schema",namespace); result.put("tables",tables);
            result.put("proposedRoleCollisions",roles); result.put("writerFunctionCollisions",functions);
            result.put("publicCreateSchemas",schemas); result.put("publicCallableDefiners",definers);
            result.put("catalogListBoundReached",bounded); result.put("installationBlockers",blockers);
            result.put("applicationDatabaseWritesPerformed",false); result.put("applicationWriterActivated",false);
            result.put("actionExecutionEnabled",false); result.put("providerCalls",0); result.put("telegramCalls",0); result.put("modelCalls",0);
            result.put("scope","CONFIGURED_DATABASE_CATALOG_ONLY_NOT_RUNTIME_IDENTITY_OR_INSTALLATION_PROOF");
            return result;
        } finally { c.rollback(); }
    }
    static void validateSchema(String schema) {
        if (schema==null || !schema.matches("[a-z][a-z0-9_]{0,62}") || schema.startsWith("pg_") || schema.equals("information_schema"))
            throw new IllegalArgumentException("Unsupported target schema");
    }
    static String validateUrl(String url) {
        // No driver escape hatches, embedded password or arbitrary connection options in the URL.
        if (url==null || !url.matches("jdbc:postgresql://[A-Za-z0-9.-]+(?::[0-9]{1,5})?/[A-Za-z0-9_-]+(?:\\?sslmode=(?:disable|allow|prefer|require|verify-ca|verify-full))?"))
            throw new IllegalArgumentException("Unsupported JDBC URL; use a reviewed connection configuration");
        return url;
    }
    static Properties properties(String user, String password) {
        if (user==null || user.isBlank() || password==null || password.isBlank()) throw new IllegalArgumentException("Database credentials missing");
        var p=new Properties(); p.setProperty("user",user); p.setProperty("password",password);
        p.setProperty("connectTimeout","5"); p.setProperty("socketTimeout","10");
        p.setProperty("readOnlyMode","always"); p.setProperty("ApplicationName","marketbrain-paper-writer-preflight");
        p.setProperty("options","-c default_transaction_read_only=on -c statement_timeout=5000 -c lock_timeout=1000 -c idle_in_transaction_session_timeout=15000");
        return p;
    }
    public static void main(String[] args) throws Exception {
        long start=System.nanoTime(); Map<String,Object> report=new LinkedHashMap<>(); int exit=1;
        report.put("version",VERSION); report.put("status","STOPPED_REVIEW_REQUIRED"); report.put("connectionAttempted",false);
        report.put("failureType",null); report.put("sqlState",null);
        report.put("applicationDatabaseWritesPerformed",false); report.put("applicationWriterActivated",false); report.put("actionExecutionEnabled",false);
        try {
            if (args.length!=0 || !"PAPER".equals(System.getenv("MARKETBRAIN_EXECUTION_MODE"))) throw new IllegalArgumentException("PAPER-only inspector");
            String schema=System.getenv().getOrDefault("MARKETBRAIN_PREFLIGHT_SCHEMA","public"); validateSchema(schema);
            String url=validateUrl(System.getenv("MARKETBRAIN_DB_URL"));
            var props=properties(System.getenv("MARKETBRAIN_DB_USERNAME"),System.getenv("MARKETBRAIN_DB_PASSWORD"));
            report.put("connectionAttempted",true);
            try (var c=DriverManager.getConnection(url,props)) { report.putAll(inspect(c,schema)); }
            exit=0;
        } catch(Exception e) {
            // Do not expose connection strings, usernames, passwords, provider errors or stack traces.
            report.put("status","STOPPED_REVIEW_REQUIRED");
            report.put("failureType",e.getClass().getSimpleName());
            if(e instanceof SQLException sql && sql.getSQLState()!=null && sql.getSQLState().matches("[A-Z0-9]{5}")) report.put("sqlState",sql.getSQLState());
        }
        report.put("observedAtUtc",Instant.now().toString()); report.put("elapsedSeconds",(System.nanoTime()-start)/1e9);
        System.out.println(new ObjectMapper().writeValueAsString(report)); System.exit(exit);
    }
}
