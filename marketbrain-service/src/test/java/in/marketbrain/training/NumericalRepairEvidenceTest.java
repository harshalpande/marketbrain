package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import java.sql.*;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalRepairEvidenceTest {
    final UUID run=UUID.randomUUID(),eventId=UUID.randomUUID(),jobId=UUID.randomUUID();
    final LocalDate from=LocalDate.parse("2024-10-22"),through=LocalDate.parse("2026-07-06");
    NumericalPriceEvidenceService.Evidence context(int events,boolean partial){
        var ledger=new ArrayList<NumericalPriceEvidenceService.ResolutionEvent>();
        for(int i=0;i<events;i++)ledger.add(new NumericalPriceEvidenceService.ResolutionEvent(new UUID(0,i+1),jobId,2L,"LARGE_MOVE",from,null,
                "REVOKE",null,null,null,Instant.EPOCH));
        var item=new NumericalPriceEvidenceService.Instrument(2,"FIXTURE",partial,List.of(),List.of(),List.of(),events,ledger,0,events,List.of("PRICE_POLICY_UNKNOWN"));
        return new NumericalPriceEvidenceService.Evidence("NUMERICAL_PRICE_EVIDENCE_V1","PRICE_POLICY_REVIEW_REQUIRED",run,"a".repeat(64),from,through,0,1,1,false,List.of(item),partial,false,false,0,0,0,"unknown");
    }
    @Test void emptyEvidenceNeverClaimsNoActionsOrQueriesReferences(){
        var prices=mock(NumericalPriceEvidenceService.class);var jdbc=mock(JdbcTemplate.class);
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(context(0,false));
        var r=new NumericalRepairEvidenceService(prices,jdbc).inspect(run,from,through,0,1);
        assertThat(r.references()).isEmpty();assertThat(r.trainingAuthorized()).isFalse();assertThat(r.partial()).isFalse();
        assertThat(r.status()).isEqualTo("REPAIR_PROVENANCE_REVIEW_REQUIRED");verifyNoInteractions(jdbc);
    }
    @Test void scopedPrimaryKeyQueryBindsIdsTimeoutAndRetainsRevocation() throws Exception {
        var prices=mock(NumericalPriceEvidenceService.class);var jdbc=mock(JdbcTemplate.class);
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(context(1,false));
        var ps=mock(PreparedStatement.class);var rs=mock(ResultSet.class);
        when(rs.getObject("id",UUID.class)).thenReturn(new UUID(0,1));when(rs.getString("evidence_source")).thenReturn("private source");
        when(rs.getString("evidence_url")).thenReturn("https://nsearchives.nseindia.com/content/circulars/CMTR64960.pdf");
        when(rs.getString("notes")).thenReturn("private reviewer text, priceDivisor=2, volumeMultiplier=2");
        doAnswer(inv->{String sql=inv.getArgument(0);assertThat(sql).contains("WHERE id IN (?)").doesNotContain("reviewed_by");
            PreparedStatementSetter setter=inv.getArgument(1);setter.setValues(ps);RowMapper<?> mapper=inv.getArgument(2);return List.of(mapper.mapRow(rs,0));})
                .when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        var r=new NumericalRepairEvidenceService(prices,jdbc).inspect(run,from,through,0,1);
        verify(ps).setObject(1,new UUID(0,1));verify(ps).setQueryTimeout(3);
        assertThat(r.priceEvidence().instruments().getFirst().latestRelevantResolutions().getFirst().eventAction()).isEqualTo("REVOKE");
        assertThat(r.references().getFirst().unverifiedFactorHints()).hasSize(2);assertThat(r.toString()).doesNotContain("private reviewer text","private source");
        assertThat(r.partial()).isFalse();assertThat(r.trainingAuthorized()).isFalse();
    }
    @Test void corporateActionReferencesAreBoundedAndRetainContextPartial() throws Exception {
        var base=context(0,false);
        var action=new NumericalPriceEvidenceService.Action(7L,"SPLIT",from,null,null,"1:2",Instant.EPOCH,"fingerprint",true);
        var item=new NumericalPriceEvidenceService.Instrument(2,"FIXTURE",true,List.of(),List.of(),List.of(action),0,List.of(),0,0,List.of("PRICE_POLICY_UNKNOWN"));
        var context=new NumericalPriceEvidenceService.Evidence(base.version(),base.status(),run,base.datasetManifestHash(),from,through,0,1,1,false,List.of(item),true,false,false,0,0,0,"unknown");
        var prices=mock(NumericalPriceEvidenceService.class);var jdbc=mock(JdbcTemplate.class);
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(context);
        var ps=mock(PreparedStatement.class);var rs=mock(ResultSet.class);
        when(rs.getLong("id")).thenReturn(7L);when(rs.getString("source_url")).thenReturn("https://nsearchives.nseindia.com/corporate/split.pdf");
        doAnswer(inv->{assertThat((String)inv.getArgument(0)).isEqualTo("SELECT id, source_url FROM corporate_action_event WHERE id IN (?) ORDER BY id");
            PreparedStatementSetter setter=inv.getArgument(1);setter.setValues(ps);RowMapper<?> mapper=inv.getArgument(2);return List.of(mapper.mapRow(rs,0));})
                .when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        var result=new NumericalRepairEvidenceService(prices,jdbc).inspect(run,from,through,0,1);
        verify(ps).setLong(1,7L);verify(ps).setQueryTimeout(3);
        assertThat(result.references()).hasSize(1);assertThat(result.references().getFirst().kind()).isEqualTo("CORPORATE_ACTION");
        assertThat(result.references().getFirst().recordId()).isEqualTo("7");assertThat(result.partial()).isTrue();
        assertThat(result.scopedActionCount()).isEqualTo(1);assertThat(result.databaseWritesPerformed()).isFalse();
    }
    @Test void capsAndMissingReferenceRowsRemainPartial(){
        var prices=mock(NumericalPriceEvidenceService.class);var jdbc=mock(JdbcTemplate.class);
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(context(201,false));
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class))).thenReturn(List.of());
        var r=new NumericalRepairEvidenceService(prices,jdbc).inspect(run,from,through,0,1);
        assertThat(r.partial()).isTrue();assertThat(r.scopedResolutionCount()).isEqualTo(201);
        verify(jdbc).query(argThat(sql->sql.chars().filter(c->c=='?').count()==200),any(PreparedStatementSetter.class),any(RowMapper.class));
        when(prices.inspectThrough(run,from,through,0,1)).thenReturn(context(1,false));
        assertThat(new NumericalRepairEvidenceService(prices,jdbc).inspect(run,from,through,0,1).partial()).isTrue();
    }
    @Test void privateUrlsAndNotesNeverLeakAndFactorClaimsAreBounded(){
        for(var url:List.of("https://nsearchives.nseindia.com/content/circulars/A.pdf?token=secret","https://user:secret@nsearchives.nseindia.com/corporate/A.pdf",
                "https://evil.example/A.pdf","https://nsearchives.nseindia.com/corporate/../A.pdf","https://nsearchives.nseindia.com:443/corporate/A.pdf","not a url")){
            var r=NumericalRepairEvidenceService.reference("RESOLUTION","1","private",url,"api_key=secret, priceDivisor=2e3, reviewedAdjustment=1:2");
            assertThat(r.publicReference()).isNull();assertThat(r.toString()).doesNotContain("secret",url,"private");
            assertThat(r.unverifiedFactorHints()).containsExactly(new NumericalRepairEvidenceService.FactorHint("reviewedAdjustment","1:2"));
        }
        assertThat(NumericalRepairEvidenceService.reference("RESOLUTION","1",null,null,null).notesPresent()).isFalse();
        assertThat(NumericalRepairEvidenceService.reference("RESOLUTION","1",null,null,"priceDivisor=2, ".repeat(20)).unverifiedFactorHints()).hasSize(8);
    }
    @Test void transactionalWiringAndHttpValidation() throws Exception {
        var prices=mock(NumericalPriceEvidenceService.class);var jdbc=mock(JdbcTemplate.class);
        new ApplicationContextRunner().withBean(NumericalPriceEvidenceService.class,()->prices).withBean(JdbcTemplate.class,()->jdbc)
                .withBean(NumericalRepairEvidenceService.class).withBean(NumericalRepairEvidenceController.class)
                .run(c->assertThat(c).hasSingleBean(NumericalRepairEvidenceController.class));
        var tx=NumericalRepairEvidenceService.class.getMethod("inspect",UUID.class,LocalDate.class,LocalDate.class,int.class,int.class).getAnnotation(Transactional.class);
        assertThat(tx.readOnly()).isTrue();assertThat(tx.timeout()).isEqualTo(60);
        var service=mock(NumericalRepairEvidenceService.class);
        var mvc=MockMvcBuilders.standaloneSetup(new NumericalRepairEvidenceController(service)).build();
        mvc.perform(get("/api/v1/training/numerical-repair-evidence")).andExpect(status().isBadRequest());
        when(service.inspect(run,from,through,0,1)).thenThrow(new IllegalArgumentException("bounded"));
        mvc.perform(get("/api/v1/training/numerical-repair-evidence").param("datasetRunId",run.toString()).param("fromDate",from.toString()).param("throughDate",through.toString()).param("limit","1")).andExpect(status().isBadRequest());
    }
}
