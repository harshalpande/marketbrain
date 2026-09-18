package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.*;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalPriceEvidenceTest {
    final UUID job=UUID.fromString("e1d9ea5d-fcb2-4a81-b839-c154bb602243");
    final UUID run=UUID.fromString("5bdbfcc1-d990-48d8-9e98-d4927596d917");
    final LocalDate from=LocalDate.of(2025,4,3),to=LocalDate.of(2026,6,5);
    NumericalPriceEvidenceService.ResolutionEvent event(String id,String action,Long instrument,Instant time) {
        return new NumericalPriceEvidenceService.ResolutionEvent(UUID.fromString(id),job,instrument,"LARGE_MOVE",from,null,action,
                action.equals("RESOLVE")?"PROVIDER_ADJUSTMENT":null,action.equals("RESOLVE")?from:null,action.equals("RESOLVE")?to:null,time);
    }
    @Test void latestRevocationWinsAndGlobalRequiresJobMembership() {
        var t=Instant.parse("2026-09-01T00:00:00Z");
        var resolved=event("00000000-0000-0000-0000-000000000001","RESOLVE",2L,t);
        var revoked=event("00000000-0000-0000-0000-000000000002","REVOKE",2L,t.plusSeconds(1));
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(resolved,revoked),2,Set.of(job),from,to)).containsExactly(revoked);
        var global=event("00000000-0000-0000-0000-000000000003","RESOLVE",null,t);
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(global),2,Set.of(),from,to)).isEmpty();
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(global),2,Set.of(job),from,to)).containsExactly(global);
    }
    @Test void uuidTieBreakMatchesPostgresUnsignedOrdering() {
        var t=Instant.parse("2026-09-01T00:00:00Z");
        var low=event("00000000-0000-0000-0000-000000000001","RESOLVE",2L,t);
        var high=event("ffffffff-0000-0000-0000-000000000001","REVOKE",2L,t);
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(high,low),2,Set.of(job),from,to)).containsExactly(high);
    }
    @Test void exclusionCanOverlapEvenWhenFindingIsOlder() {
        var e=new NumericalPriceEvidenceService.ResolutionEvent(UUID.randomUUID(),job,2L,"LARGE_MOVE",from.minusDays(10),null,
                "RESOLVE","FEATURE_WINDOW_EXCLUDED",from.minusDays(10),from.plusDays(2),Instant.now());
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(e),2,Set.of(job),from,to)).containsExactly(e);
        assertThat(NumericalPriceEvidenceService.latestRelevant(List.of(e),3,Set.of(job),from,to)).isEmpty();
    }
    @Test void completedSchedulingRangeIsNotInferredAcrossGapsOrFailures() {
        var a=new NumericalPriceEvidenceService.Chunk(job,from,from.plusDays(10),"COMPLETED",10,0);
        var b=new NumericalPriceEvidenceService.Chunk(job,from.plusDays(11),to,"COMPLETED",10,0);
        assertThat(NumericalPriceEvidenceService.covers(List.of(b,a),from,to)).isTrue();
        assertThat(NumericalPriceEvidenceService.covers(List.of(a),from,to)).isFalse();
        assertThat(NumericalPriceEvidenceService.covers(List.of(a,new NumericalPriceEvidenceService.Chunk(job,from.plusDays(12),to,"COMPLETED",10,0)),from,to)).isFalse();
        assertThat(NumericalPriceEvidenceService.covers(List.of(new NumericalPriceEvidenceService.Chunk(job,from,to,"FAILED",10,0)),from,to)).isFalse();
        assertThat(NumericalPriceEvidenceService.covers(List.of(new NumericalPriceEvidenceService.Chunk(job,from,to,"COMPLETED",10,1)),from,to)).isFalse();
    }
    @Test void invalidRequestBeforeAnyQuery() {
        var jdbc=mock(JdbcTemplate.class);var s=new NumericalPriceEvidenceService(jdbc);
        assertThatThrownBy(()->s.inspect(null,from,0,4)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->s.inspect(run,null,0,4)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->s.inspect(run,from,0,5)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc);
    }
    @Test void queriesBindScopeMapEvidenceAndNeverAuthorizeAdjustments() throws Exception {
        var jdbc=mock(JdbcTemplate.class);var statement=mock(PreparedStatement.class);var rs=mock(ResultSet.class);
        when(rs.getObject("as_of",LocalDate.class)).thenReturn(to);when(rs.getString("dataset_manifest_hash")).thenReturn("a".repeat(64));when(rs.getInt("instrument_count")).thenReturn(1);
        when(rs.getLong("instrument_id")).thenReturn(2L);when(rs.getString("symbol")).thenReturn("FIXTURE");
        when(rs.getObject("id",UUID.class)).thenReturn(job);when(rs.getObject("job_id",UUID.class)).thenReturn(job);
        when(rs.getObject("instrument_id",Long.class)).thenReturn(2L);
        when(rs.getString("status")).thenReturn("COMPLETED");when(rs.getString("job_type")).thenReturn("EXPANSION");
        for(String field:List.of("requested_from","from_date","finding_date","exclusion_from"))when(rs.getObject(field,LocalDate.class)).thenReturn(from);
        for(String field:List.of("requested_to","to_date","exclusion_to"))when(rs.getObject(field,LocalDate.class)).thenReturn(to);
        when(rs.getString("event_action")).thenReturn("RESOLVE");when(rs.getString("resolution_type")).thenReturn("PROVIDER_ADJUSTMENT");when(rs.getString("finding_type")).thenReturn("LARGE_MOVE");
        when(rs.getTimestamp("created_at")).thenReturn(Timestamp.from(Instant.parse("2026-09-01T00:00:00Z")));
        List<String> sqls=new ArrayList<>();
        doAnswer(inv->{String sql=inv.getArgument(0);sqls.add(sql);PreparedStatementSetter setter=inv.getArgument(1);setter.setValues(statement);
            if(sql.equals(NumericalPriceEvidenceService.ACTIONS_SQL))return List.of();
            RowMapper<?> mapper=inv.getArgument(2);return List.of(mapper.mapRow(rs,0));
        }).when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        var result=new NumericalPriceEvidenceService(jdbc).inspect(run,from,0,4);
        var item=result.instruments().getFirst();
        assertThat(item.jobLinks().getFirst().savedReportReference()).startsWith("E35_");
        assertThat(item.jobLinks().getFirst().completedChunkRangeCoversScope()).isTrue();
        assertThat(item.overlappingActiveExclusionCount()).isEqualTo(1);
        assertThat(item.remainingGates()).contains("CORPORATE_ACTION_COVERAGE_UNKNOWN","CURRENT_EXCLUSION_OVERLAPS_SCOPE","NO_VERIFIED_ADJUSTMENT_FACTORS_OR_EXECUTABLE_PRICE_BINDING");
        assertThat(result.trainingAuthorized()).isFalse();assertThat(result.databaseWritesPerformed()).isFalse();
        assertThat(sqls).hasSize(6);verify(statement,times(6)).setQueryTimeout(3);
        assertThat(sqls.get(4)).contains("job_id IN (?) AND instrument_id = ?","LIMIT 201");
        assertThat(sqls.get(5)).contains("LIMIT 1001","instrument_id IS NULL").doesNotContain("event_action = 'RESOLVE'");
        verify(statement,atLeastOnce()).setObject(1,job);verify(statement,atLeastOnce()).setObject(2,from);
        verify(jdbc,never()).update(anyString());
    }
    @Test void noJobsIsUnknownNotPassAndActionSentinelMarksPartial() {
        var jdbc=mock(JdbcTemplate.class);
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class)))
                .thenReturn(List.of(new NumericalHistoryCoverageService.Run(to,"hash",1)))
                .thenReturn(List.of(new NumericalFeatureSnapshotService.Item(2,"FIXTURE")))
                .thenReturn(List.of())
                .thenReturn(Collections.nCopies(501,new NumericalPriceEvidenceService.Action(1,"SPLIT",from,null,null,"2:1",null,"hash",true)));
        var result=new NumericalPriceEvidenceService(jdbc).inspect(run,from,0,1);
        assertThat(result.partial()).isTrue();assertThat(result.instruments().getFirst().jobLinks()).isEmpty();
        assertThat(result.instruments().getFirst().remainingGates()).contains("PARTIAL_CAPPED_EVIDENCE","NO_OVERLAPPING_BACKFILL_MEMBERSHIP_FOUND");
        assertThat(result.trainingAuthorized()).isFalse();
    }
    @Test void readOnlyWiringAndHttpInputGuards() throws Exception {
        var tx=NumericalPriceEvidenceService.class.getMethod("inspect",UUID.class,LocalDate.class,int.class,int.class).getAnnotation(Transactional.class);
        assertThat(tx.readOnly()).isTrue();assertThat(tx.timeout()).isEqualTo(45);assertThat(tx.isolation()).isEqualTo(Isolation.REPEATABLE_READ);
        new ApplicationContextRunner().withBean(JdbcTemplate.class,()->mock(JdbcTemplate.class)).withBean(NumericalPriceEvidenceService.class)
                .withBean(NumericalPriceEvidenceController.class).run(c->assertThat(c).hasNotFailed().hasSingleBean(NumericalPriceEvidenceController.class));
        var service=mock(NumericalPriceEvidenceService.class);var mvc=MockMvcBuilders.standaloneSetup(new NumericalPriceEvidenceController(service)).build();
        mvc.perform(get("/api/v1/training/numerical-price-evidence").param("datasetRunId",run.toString())).andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/training/numerical-price-evidence").param("datasetRunId",run.toString()).param("fromDate",from.toString())).andExpect(status().isOk());
        verify(service).inspect(run,from,0,4);
    }
}
