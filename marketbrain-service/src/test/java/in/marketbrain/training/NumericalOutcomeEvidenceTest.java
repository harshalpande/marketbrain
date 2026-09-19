package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.*;
import java.math.BigDecimal;
import java.sql.*;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalOutcomeEvidenceTest {
    final UUID run=UUID.fromString("5bdbfcc1-d990-48d8-9e98-d4927596d917");
    final LocalDate asOf=LocalDate.of(2026,6,5),from=LocalDate.of(2025,4,3),through=LocalDate.of(2026,7,17);
    final String manifest="a".repeat(64);
    NumericalPriceEvidenceService.Evidence price(boolean partial){
        return new NumericalPriceEvidenceService.Evidence("NUMERICAL_PRICE_EVIDENCE_V1","PRICE_POLICY_REVIEW_REQUIRED",run,manifest,from,through,0,1,0,false,
                List.of(new NumericalPriceEvidenceService.Instrument(2,"FIXTURE",partial,List.of(),List.of(),List.of(),0,List.of(),0,0,List.of("CORPORATE_ACTION_COVERAGE_UNKNOWN"))),partial,false,false,0,0,0,"unknown");
    }
    NumericalFeatureSnapshot.SourceBar bar(){return new NumericalFeatureSnapshot.SourceBar(10,asOf.plusDays(3),"UPSTOX",Instant.parse("2026-09-01T00:00:00Z"),BigDecimal.TEN,BigDecimal.TEN,BigDecimal.TEN,BigDecimal.TEN,BigDecimal.ONE,false);}
    void queries(JdbcTemplate jdbc,List<?> bars){
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class)))
                .thenReturn(List.of(new NumericalOutcomeEvidenceService.Run(asOf,asOf.plusDays(95),manifest,1)))
                .thenReturn(List.of(new NumericalFeatureSnapshotService.Item(2,"FIXTURE"))).thenReturn(bars);
    }
    @Test void invalidInputNeverQueries(){
        var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);var s=new NumericalOutcomeEvidenceService(jdbc,prices);
        assertThatThrownBy(()->s.inspect(null,from,through,0,1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->s.inspect(run,from,through,0,5)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->s.inspect(run,from,null,0,1)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc,prices);
    }
    @Test void dateBoundsAndStoredLabelThroughGuardBeforeBarQueries(){
        for(var invalid:List.of(asOf,asOf.plusDays(46),asOf.minusDays(1))){
            var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);queries(jdbc,List.of());
            assertThatThrownBy(()->new NumericalOutcomeEvidenceService(jdbc,prices).inspect(run,from,invalid,0,1)).isInstanceOf(IllegalArgumentException.class);
            verify(jdbc,times(1)).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));verifyNoInteractions(prices);
        }
        var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class))).thenReturn(List.of(new NumericalOutcomeEvidenceService.Run(asOf,asOf.plusDays(10),manifest,1)));
        assertThatThrownBy(()->new NumericalOutcomeEvidenceService(jdbc,prices).inspect(run,from,through,0,1)).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void queryBindsOutcomeOnlyWindowAndMapsCanonicalBar() throws Exception {
        var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);var statement=mock(PreparedStatement.class);var rs=mock(ResultSet.class);
        when(rs.getObject("as_of",LocalDate.class)).thenReturn(asOf);when(rs.getObject("label_through",LocalDate.class)).thenReturn(asOf.plusDays(95));
        when(rs.getString("dataset_manifest_hash")).thenReturn(manifest);when(rs.getInt("instrument_count")).thenReturn(1);
        when(rs.getLong("instrument_id")).thenReturn(2L);when(rs.getString("symbol")).thenReturn("FIXTURE");
        when(rs.getLong("id")).thenReturn(10L);when(rs.getObject("trading_date",LocalDate.class)).thenReturn(asOf.plusDays(3));when(rs.getString("source_code")).thenReturn("UPSTOX");
        for(var field:List.of("open_price","high_price","low_price","close_price","volume"))when(rs.getBigDecimal(field)).thenReturn(BigDecimal.TEN);
        doAnswer(inv->{PreparedStatementSetter setter=inv.getArgument(1);setter.setValues(statement);RowMapper<?> mapper=inv.getArgument(2);return List.of(mapper.mapRow(rs,0));})
                .when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(price(false));
        var result=new NumericalOutcomeEvidenceService(jdbc,prices).inspect(run,from,through,0,1);
        assertThat(result.outcomeFrom()).isEqualTo(asOf.plusDays(1));assertThat(result.instruments().getFirst().canonicalBars()).hasSize(1);
        assertThat(result.trainingAuthorized()).isFalse();assertThat(result.databaseWritesPerformed()).isFalse();assertThat(result.partial()).isFalse();
        verify(statement).setTimestamp(5,Timestamp.from(asOf.plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
        verify(statement).setTimestamp(6,Timestamp.from(through.plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
        verify(statement).setQueryTimeout(5);verify(statement,times(2)).setQueryTimeout(3);
        assertThat(NumericalOutcomeEvidenceService.BARS_SQL).contains("LIMIT 201","c.opened_at >= ? AND c.opened_at < ?");
    }
    @Test void sentinelAndPricePartialCannotBecomeComplete(){
        for(boolean pricePartial:List.of(false,true)){
            var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);
            queries(jdbc,pricePartial?List.of(bar()):Collections.nCopies(201,bar()));when(prices.inspectThrough(run,from,through,0,1)).thenReturn(price(pricePartial));
            var result=new NumericalOutcomeEvidenceService(jdbc,prices).inspect(run,from,through,0,1);
            assertThat(result.partial()).isTrue();assertThat(result.instruments().getFirst().truncated()).isEqualTo(!pricePartial);assertThat(result.trainingAuthorized()).isFalse();
        }
    }
    @Test void emptyBarsRemainEmptyNotSynthetic(){
        var jdbc=mock(JdbcTemplate.class);var prices=mock(NumericalPriceEvidenceService.class);queries(jdbc,List.of());when(prices.inspectThrough(run,from,through,0,1)).thenReturn(price(false));
        assertThat(new NumericalOutcomeEvidenceService(jdbc,prices).inspect(run,from,through,0,1).instruments().getFirst().canonicalBars()).isEmpty();
    }
    @Test void priceWindowExtendsBeyondOriginalAsOfAndPreservesOldEndpoint(){
        var jdbc=mock(JdbcTemplate.class);
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class)))
                .thenReturn(List.of(new NumericalHistoryCoverageService.Run(asOf,manifest,1)))
                .thenReturn(List.of(new NumericalFeatureSnapshotService.Item(2,"FIXTURE"))).thenReturn(List.of()).thenReturn(List.of());
        var e=new NumericalPriceEvidenceService(jdbc).inspectThrough(run,from,through,0,1);
        assertThat(e.throughDate()).isEqualTo(through);assertThat(e.trainingAuthorized()).isFalse();
        assertThatThrownBy(()->new NumericalPriceEvidenceService(jdbc).inspectThrough(run,from,null,0,1)).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void readOnlyBeanWiringAndHttpGuards() throws Exception {
        var tx=NumericalOutcomeEvidenceService.class.getMethod("inspect",UUID.class,LocalDate.class,LocalDate.class,int.class,int.class).getAnnotation(Transactional.class);
        assertThat(tx.readOnly()).isTrue();assertThat(tx.timeout()).isEqualTo(60);assertThat(tx.isolation()).isEqualTo(Isolation.REPEATABLE_READ);
        new ApplicationContextRunner().withBean(JdbcTemplate.class,()->mock(JdbcTemplate.class)).withBean(NumericalPriceEvidenceService.class)
                .withBean(NumericalOutcomeEvidenceService.class).withBean(NumericalOutcomeEvidenceController.class).run(c->assertThat(c).hasNotFailed());
        var service=mock(NumericalOutcomeEvidenceService.class);var mvc=MockMvcBuilders.standaloneSetup(new NumericalOutcomeEvidenceController(service)).build();
        mvc.perform(get("/api/v1/training/numerical-outcome-evidence").param("datasetRunId",run.toString())).andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/training/numerical-outcome-evidence").param("datasetRunId",run.toString()).param("featureFrom",from.toString()).param("throughDate",through.toString())).andExpect(status().isOk());
        verify(service).inspect(run,from,through,0,4);
    }
}
