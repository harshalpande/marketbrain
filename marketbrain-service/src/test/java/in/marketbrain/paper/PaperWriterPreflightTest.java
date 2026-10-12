package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.sql.*;
import java.nio.file.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperWriterPreflightTest {
    static Map<String,Object> row(Object... fields) {
        Map<String,Object> r=new LinkedHashMap<>();
        for(int i=0;i<fields.length;i+=2) r.put((String)fields[i],fields[i+1]); return r;
    }
    static class Fixture {
        final Connection c=mock(Connection.class);
        final Map<String,Object> session=row("readOnly",true,"repeatableRead",true,"serverVersionNumber",160000,
                "resolvedSchema","public","unchangedSessionIdentity",true,"superuser",false,"createRole",true,
                "publicDatabaseCreate",false,"publicDatabaseTemp",false);
        final Map<String,Object> namespace=row("schemaName","public","currentRoleCreate",true,"currentRoleOwnerMembership",true,"publicCreate",false);
        final Map<String,Object> table=row("tableName","table","kind","r","rowSecurity",false,"forceRowSecurity",false,
                "currentRoleOwnerMembership",true,"currentRoleSelect",true,"publicSelect",false,"publicWrite",false);
        List<Map<String,Object>> roles=List.of(),functions=List.of(),schemas=List.of(),definers=List.of();
        boolean absent;
        final List<PreparedStatement> statements=new ArrayList<>();
        Fixture()throws Exception {
            when(c.prepareStatement(anyString())).thenAnswer(call->{
                String sql=call.getArgument(0); var p=mock(PreparedStatement.class); statements.add(p);
                Map<Integer,String> args=new HashMap<>();
                doAnswer(a->{args.put(a.getArgument(0),a.getArgument(1));return null;}).when(p).setString(anyInt(),anyString());
                when(p.executeQuery()).thenAnswer(a->{
                    List<Map<String,Object>> records=switch(sql) {
                        case PaperWriterPreflight.SESSION -> List.of(session);
                        case PaperWriterPreflight.SCHEMA -> List.of(namespace);
                        case PaperWriterPreflight.TABLE -> {var t=new LinkedHashMap<>(table);t.put("tableName",args.get(2));yield absent?List.of():List.of(t);}
                        case PaperWriterPreflight.COLLISIONS -> roles;
                        case PaperWriterPreflight.FUNCTIONS -> functions;
                        case PaperWriterPreflight.PUBLIC_SCHEMAS -> schemas;
                        case PaperWriterPreflight.PUBLIC_DEFINERS -> definers;
                        default -> throw new AssertionError("Non-allowlisted query");
                    };
                    return result(records);
                });return p;
            });
        }
        Map<String,Object> inspect()throws Exception{return PaperWriterPreflight.inspect(c,"public");}
    }
    static ResultSet result(List<Map<String,Object>> records)throws Exception {
        var rs=mock(ResultSet.class);var meta=mock(ResultSetMetaData.class);when(rs.getMetaData()).thenReturn(meta);
        List<String> keys=records.isEmpty()?List.of():new ArrayList<>(records.getFirst().keySet());
        when(meta.getColumnCount()).thenReturn(keys.size());when(meta.getColumnLabel(anyInt())).thenAnswer(a->keys.get((int)a.getArgument(0)-1));
        int[] index={-1};when(rs.next()).thenAnswer(a->++index[0]<records.size());
        when(rs.getObject(anyInt())).thenAnswer(a->records.get(index[0]).get(keys.get((int)a.getArgument(0)-1)));return rs;
    }
    @SuppressWarnings("unchecked") static List<String> blockers(Map<String,Object> r){return (List<String>)r.get("installationBlockers");}
    @Test void successfulInspectionNeverMeansActivation()throws Exception {
        var f=new Fixture();var r=f.inspect();
        assertEquals("CATALOG_REVIEW_COMPLETE_APPLICATION_ACTIVATION_BLOCKED",r.get("status"));
        for(String flag:List.of("applicationDatabaseWritesPerformed","applicationWriterActivated","actionExecutionEnabled"))assertEquals(false,r.get(flag));
        assertTrue(blockers(r).isEmpty());assertEquals(12,((List<?>)r.get("tables")).size());
        var order=inOrder(f.c);order.verify(f.c).setReadOnly(true);order.verify(f.c).setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);order.verify(f.c).setAutoCommit(false);order.verify(f.c).prepareStatement(PaperWriterPreflight.SESSION);
        verify(f.c).rollback();verify(f.c,never()).commit();verify(f.c,never()).createStatement();
        assertEquals(18,f.statements.size());for(var p:f.statements){verify(p).setQueryTimeout(5);verify(p).setMaxRows(21);verify(p).close();verify(p,never()).executeUpdate();}
    }
    @ParameterizedTest @ValueSource(strings={"readOnly","repeatableRead","unchangedSessionIdentity"})
    void sessionGuardStopsBeforeOtherReads(String field)throws Exception {
        var f=new Fixture();f.session.put(field,false);assertThrows(SQLException.class,f::inspect);verify(f.c).rollback();assertEquals(1,f.statements.size());
    }
    @Test void readFailureRollsBackAndDoesNotCommit()throws Exception {
        var f=new Fixture();when(f.c.prepareStatement(PaperWriterPreflight.SCHEMA)).thenThrow(new SQLException("secret"));
        assertThrows(SQLException.class,f::inspect);verify(f.c).rollback();verify(f.c,never()).commit();
    }
    @Test void noRoleAuthorityIsReportedNotWorkedAround()throws Exception {
        var f=new Fixture();f.session.put("createRole",false);assertTrue(blockers(f.inspect()).contains("ROLE_PROVISIONING_REQUIRES_AUTHORIZED_ADMIN"));
    }
    @Test void publicPrivilegesAreNotSilentlyRevoked()throws Exception {
        var f=new Fixture();f.session.put("publicDatabaseTemp",true);f.session.put("publicDatabaseCreate",true);
        f.table.put("publicSelect",true);f.schemas=List.of(row("schemaName","public"));f.definers=List.of(row("schemaName","public","functionName","unreviewed"));
        var b=blockers(f.inspect());assertTrue(b.contains("PUBLIC_TEMP_REQUIRES_IMPACT_REVIEW"));assertTrue(b.contains("PUBLIC_DATABASE_CREATE_REQUIRES_IMPACT_REVIEW"));
        assertTrue(b.contains("PUBLIC_SCHEMA_CREATE_REQUIRES_IMPACT_REVIEW"));assertTrue(b.contains("PUBLIC_SECURITY_DEFINER_REQUIRES_IMPACT_REVIEW"));
        assertTrue(b.contains("PUBLIC_TABLE_ACCESS_REQUIRES_IMPACT_REVIEW:paper_approval_delivery"));
    }
    @Test void roleAndFunctionCollisionsBlockAutomaticAdoption()throws Exception {
        var f=new Fixture();f.roles=List.of(row("roleName","marketbrain_paper_review_writer"));f.functions=List.of(row("functionName","paper_review_record"));
        var b=blockers(f.inspect());assertTrue(b.contains("PROPOSED_ROLE_NAME_COLLISION_DO_NOT_ADOPT"));assertTrue(b.contains("EXISTING_WRITER_FUNCTIONS_DO_NOT_REPLACE"));
    }
    @Test void missingTablesAndRlsAndUnownedTablesAreExplicit()throws Exception {
        var f=new Fixture();f.absent=true;assertEquals(12,blockers(f.inspect()).size());
        f=new Fixture();f.table.put("rowSecurity",true);f.table.put("currentRoleOwnerMembership",false);f.table.put("kind","v");
        var b=blockers(f.inspect());assertTrue(b.contains("ROW_SECURITY_REQUIRES_REVIEW:paper_portfolio"));assertTrue(b.contains("TABLE_AUTHORITY_REQUIRES_REVIEW:paper_portfolio"));assertTrue(b.contains("UNREVIEWED_RELATION_KIND:paper_portfolio"));
    }
    @Test void listBoundIsNotInterpretedAsCompleteInventory()throws Exception {
        var f=new Fixture();f.definers=Collections.nCopies(21,row("schemaName","public","functionName","f"));
        var r=f.inspect();assertEquals(true,r.get("catalogListBoundReached"));assertTrue(blockers(r).contains("CATALOG_LIST_BOUND_REACHED_REVIEW_INCOMPLETE"));
    }
    @Test void schemaMismatchBlocksAdoption()throws Exception {
        var f=new Fixture();f.session.put("resolvedSchema","another");assertTrue(blockers(f.inspect()).contains("CONFIGURED_SCHEMA_DIFFERS_FROM_SEARCH_PATH"));
    }
    @ParameterizedTest @ValueSource(strings={"pg_catalog","information_schema","public;DELETE","MixedCase","","public.other"})
    void schemaRejectedBeforeDatabaseWork(String schema) {
        var c=mock(Connection.class);assertThrows(IllegalArgumentException.class,()->PaperWriterPreflight.inspect(c,schema));verifyNoInteractions(c);
    }
    @Test void validConnectionPropertiesPinReadOnlyAndDeadlines() {
        var p=PaperWriterPreflight.properties("fixture","not-a-real-secret");assertEquals("always",p.getProperty("readOnlyMode"));
        assertEquals("5",p.getProperty("connectTimeout"));assertEquals("10",p.getProperty("socketTimeout"));assertTrue(p.getProperty("options").contains("default_transaction_read_only=on"));
        assertEquals("jdbc:postgresql://host.docker.internal:5432/marketbrain",PaperWriterPreflight.validateUrl("jdbc:postgresql://host.docker.internal:5432/marketbrain"));
        assertDoesNotThrow(()->PaperWriterPreflight.validateUrl("jdbc:postgresql://server/db?sslmode=require"));
        assertThrows(IllegalArgumentException.class,()->PaperWriterPreflight.properties("u",""));
    }
    @ParameterizedTest @ValueSource(strings={"jdbc:postgresql://host/db?options=x","jdbc:postgresql://u:p@host/db","jdbc:postgresql://host/db?password=secret","jdbc:postgresql://host/db?socketTimeout=0","jdbc:postgresql://host/db?readOnlyMode=ignore","jdbc:postgresql://host/db?sslmode=require&options=x","jdbc:h2:mem:test",""})
    void connectionEscapeHatchesAreRejected(String url){assertThrows(IllegalArgumentException.class,()->PaperWriterPreflight.validateUrl(url));}
    @Test void sqlOnlyReadsCatalogsWithNoUserTableRows() {
        for(String sql:List.of(PaperWriterPreflight.SESSION,PaperWriterPreflight.SCHEMA,PaperWriterPreflight.TABLE,PaperWriterPreflight.COLLISIONS,PaperWriterPreflight.FUNCTIONS,PaperWriterPreflight.PUBLIC_SCHEMAS,PaperWriterPreflight.PUBLIC_DEFINERS)) {
            assertTrue(sql.stripLeading().startsWith("SELECT"));assertFalse(sql.contains(";"));assertFalse(sql.contains("FOR UPDATE"));assertFalse(sql.contains("FROM paper_"));
            assertFalse(sql.contains("pg_authid"));assertFalse(sql.contains("rolpassword"));assertFalse(sql.contains("pg_get_functiondef"));
        }
        assertTrue(PaperWriterPreflight.TABLE.contains("has_any_column_privilege"));
    }
    @SuppressWarnings("unchecked")
    @Test void standaloneComposeCannotStartApplicationOrMountSecrets() throws Exception {
        Map<String,Object> compose=new org.yaml.snakeyaml.Yaml().load(Files.readString(Path.of("../compose.paper-writer-preflight.yaml")));
        var services=(Map<String,Object>)compose.get("services");assertEquals(Set.of("paper-writer-preflight"),services.keySet());
        var service=(Map<String,Object>)services.get("paper-writer-preflight");
        for(String forbidden:List.of("ports","volumes","depends_on","privileged","env_file","network_mode"))assertFalse(service.containsKey(forbidden));
        assertEquals(true,service.get("read_only"));assertEquals(List.of("ALL"),service.get("cap_drop"));
        assertEquals(List.of("no-new-privileges:true"),service.get("security_opt"));
        var env=(Map<String,Object>)service.get("environment");
        assertEquals(Set.of("MARKETBRAIN_DB_URL","MARKETBRAIN_DB_USERNAME","MARKETBRAIN_DB_PASSWORD","MARKETBRAIN_EXECUTION_MODE","MARKETBRAIN_PREFLIGHT_SCHEMA"),env.keySet());
        assertEquals("PAPER",env.get("MARKETBRAIN_EXECUTION_MODE"));
        String dockerfile=Files.readString(Path.of("Dockerfile.paper-writer-preflight"));
        assertTrue(dockerfile.contains("USER 65532:65532"));assertTrue(dockerfile.contains("in.marketbrain.paper.PaperWriterPreflight"));
        assertFalse(dockerfile.contains("SpringApplication"));
    }
}
