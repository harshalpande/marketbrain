package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.math.BigDecimal;
import java.nio.file.Path;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalResearchExportTest {
    static final ObjectMapper MAPPER=new ObjectMapper().findAndRegisterModules()
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    static List<LocalDate> sessions() throws Exception {
        var root=Path.of(System.getProperty("user.dir"));
        if(!root.resolve("ops/data").toFile().exists())root=root.getParent();
        var calendar=MAPPER.readTree(root.resolve("ops/data/nse-cm-calendar-20250401-20260605-v1.json").toFile());
        var extension=MAPPER.readTree(root.resolve("ops/data/nse-cm-outcome-calendar-20260606-20260717-v1.json").toFile());
        var closed=new HashSet<LocalDate>();var special=new HashSet<LocalDate>();
        calendar.get("closures").forEach(n->closed.add(LocalDate.parse(n.get("date").asText())));
        extension.get("closures").forEach(n->closed.add(LocalDate.parse(n.asText())));
        calendar.get("specialSessions").forEach(n->special.add(LocalDate.parse(n.get("date").asText())));
        return LocalDate.parse("2025-04-01").datesUntil(LocalDate.parse("2026-07-18"))
                .filter(d->special.contains(d)||d.getDayOfWeek().getValue()<=5&&!closed.contains(d)).toList();
    }
    NumericalResearchExport.Input input() throws Exception {
        var days=sessions();var bars=new ArrayList<NumericalResearchExport.Bar>();int id=1;
        for(var d:days)bars.add(bar(id++,d,100,false));
        return new NumericalResearchExport.Input(UUID.randomUUID(),"a".repeat(64),"b".repeat(64),"c".repeat(64),days,
                List.of(new NumericalResearchExport.Instrument(1,"FIXTURE",bars)));
    }
    NumericalResearchExport.Bar bar(long id,LocalDate d,int close,Boolean excluded){
        return new NumericalResearchExport.Bar(id,d,"UPSTOX",Instant.parse("2026-09-01T00:00:00Z"),BigDecimal.valueOf(100),
                BigDecimal.valueOf(Math.max(close,100)),BigDecimal.valueOf(Math.min(close,100)),BigDecimal.valueOf(close),BigDecimal.valueOf(1000),excluded);
    }
    @Test void exportsAllDatesKeepsTrainingBlockedAndDeterministic() throws Exception {
        var i=input();var r=new NumericalResearchExport().build(i);
        assertThat(r.decisionDateCount()).isEqualTo(38);assertThat(r.candidateRowCount()).isEqualTo(38);
        assertThat(r.completeArithmeticRowCount()).isEqualTo(38);assertThat(r.blockedRowCount()).isZero();
        assertThat(r.trainingAuthorized()).isFalse();assertThat(r.certifiedLabelCount()).isZero();
        assertThat(r.databaseQueryCount()+r.modelCallCount()+r.providerCallCount()+r.ordersCreated()).isZero();
        assertThat(r.rows().getFirst().featureSnapshot().receivedAfterCutoffCount()).isEqualTo(252);
        assertThat(r.rows().getLast().outcome().exitDate()).isEqualTo(LocalDate.parse("2026-07-06"));
        assertThat(new NumericalResearchExport().build(i)).isEqualTo(r);
    }
    @Test void changingFuturePricesCannotChangeEarlierFeatures() throws Exception {
        var i=input();var before=new NumericalResearchExport().build(i);
        var bars=i.instruments().getFirst().bars();int n=i.sessions().indexOf(LocalDate.parse("2026-06-08"));
        bars.set(n,bar(n+1,i.sessions().get(n),200,false));
        var after=new NumericalResearchExport().build(i);
        assertThat(after.rows().stream().map(NumericalResearchExport.Row::featureSnapshot).toList())
                .isEqualTo(before.rows().stream().map(NumericalResearchExport.Row::featureSnapshot).toList());
        assertThat(after.rows()).isNotEqualTo(before.rows());
    }
    @Test void missingOrExcludedPathNeverShiftsAndCalendarGapBlocksFeatures() throws Exception {
        var i=input();var bars=i.instruments().getFirst().bars();
        bars.removeIf(b->b.date().equals(LocalDate.parse("2026-06-08")));
        var r=new NumericalResearchExport().build(i);
        assertThat(r.rows().getLast().outcome().status()).isEqualTo("MISSING_BAR");
        assertThat(r.rows().getLast().outcome().entryDate()).isEqualTo(LocalDate.parse("2026-06-08"));
        i=input();bars=i.instruments().getFirst().bars();int n=i.sessions().indexOf(LocalDate.parse("2026-06-08"));
        bars.set(n,bar(n+1,i.sessions().get(n),100,true));
        assertThat(new NumericalResearchExport().build(i).rows().getLast().outcome().status()).isEqualTo("EXCLUDED_BAR");
        i=input();i.instruments().getFirst().bars().remove(100);
        assertThat(new NumericalResearchExport().build(i).completeArithmeticRowCount()).isZero();
    }
    @Test void rejectsCalendarChangesDuplicatesMissingFlagsAndUnboundedNumbers() throws Exception {
        var good=input();var days=new ArrayList<>(good.sessions());Collections.swap(days,0,1);
        var bad=new NumericalResearchExport.Input(good.datasetRunId(),good.datasetManifestHash(),good.featureEvidenceSha256(),good.outcomeEvidenceSha256(),days,good.instruments());
        assertThatThrownBy(()->new NumericalResearchExport().build(bad)).isInstanceOf(IllegalArgumentException.class);
        for(int kind=0;kind<3;kind++) {
            var i=input();var bars=i.instruments().getFirst().bars();
            if(kind==0)bars.set(1,bars.getFirst());
            if(kind==1)bars.set(0,bar(1,bars.getFirst().date(),100,null));
            if(kind==2){var b=bars.getFirst();bars.set(0,new NumericalResearchExport.Bar(1,b.date(),b.source(),b.receivedAt(),new BigDecimal("1e999"),b.high(),b.low(),b.close(),b.volume(),false));}
            assertThatThrownBy(()->new NumericalResearchExport().build(i)).isInstanceOf(IllegalArgumentException.class);
        }
    }
    @Test void endpointWiringInvalidBodyAndByteCap() throws Exception {
        new org.springframework.boot.test.context.runner.ApplicationContextRunner()
                .withBean(ObjectMapper.class,()->MAPPER).withBean(NumericalResearchExportController.class)
                .run(context->assertThat(context).hasSingleBean(NumericalResearchExportController.class));
        var mvc=MockMvcBuilders.standaloneSetup(new NumericalResearchExportController(MAPPER)).build();
        mvc.perform(post("/api/v1/training/numerical-research-export").contentType(MediaType.APPLICATION_JSON).content(MAPPER.writeValueAsBytes(input()))).andExpect(status().isOk());
        mvc.perform(post("/api/v1/training/numerical-research-export").contentType(MediaType.APPLICATION_JSON).content("{}" )).andExpect(status().isBadRequest());
        mvc.perform(post("/api/v1/training/numerical-research-export").contentType(MediaType.APPLICATION_JSON).content(new byte[2*1024*1024+1])).andExpect(status().isPayloadTooLarge());
    }
    @Test void excludesConcurrentRequestsWithoutQueueAndReleasesSlotOnError() throws Exception {
        var controller=new NumericalResearchExportController(MAPPER);
        var first=org.mockito.Mockito.mock(jakarta.servlet.http.HttpServletRequest.class);
        var second=new org.springframework.mock.web.MockHttpServletRequest();second.setContent("{}".getBytes());
        org.mockito.Mockito.when(first.getInputStream()).thenAnswer(invocation->{
            assertThatThrownBy(()->controller.export(second)).isInstanceOf(org.springframework.web.server.ResponseStatusException.class)
                    .hasMessageContaining("429");
            throw new java.io.IOException("fixture read failure");
        });
        assertThatThrownBy(()->controller.export(first)).isInstanceOf(java.io.IOException.class);
        assertThatThrownBy(()->controller.export(second)).isInstanceOf(org.springframework.web.server.ResponseStatusException.class)
                .hasMessageContaining("400");
    }
    @Test void invalidOhlcAndSensitivityAreExplicitAndRowsAreRetained() throws Exception {
        var i=input();var bars=i.instruments().getFirst().bars();int n=i.sessions().indexOf(LocalDate.parse("2026-06-08"));
        bars.set(n,bar(n+1,i.sessions().get(n),0,false));
        var r=new NumericalResearchExport().build(i);
        assertThat(r.candidateRowCount()).isEqualTo(38);assertThat(r.blockedRowCount()).isPositive();
        assertThat(r.rows().getLast().outcome().status()).isEqualTo("INVALID_OHLC");
        r=new NumericalResearchExport().build(input());
        assertThat(r.rows().getFirst().outcome().costSensitivity().get(3).indicativeNetPercent()).isEqualByComparingTo("-1");
    }
}
