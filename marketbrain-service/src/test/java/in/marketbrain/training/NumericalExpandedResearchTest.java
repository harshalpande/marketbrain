package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.*;
import static in.marketbrain.training.NumericalResearchExportTest.MAPPER;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalExpandedResearchTest {
    static List<LocalDate> sessions() throws Exception {
        var root=Path.of(System.getProperty("user.dir"));if(!root.resolve("ops/data").toFile().exists())root=root.getParent();
        var early=MAPPER.readTree(root.resolve("ops/data/nse-cm-early-calendar-20241022-20250331-v1.json").toFile());
        var closed=new HashSet<LocalDate>();var special=new HashSet<LocalDate>();
        early.get("closures").forEach(n->closed.add(LocalDate.parse(n.asText())));early.get("specialSessions").forEach(n->special.add(LocalDate.parse(n.asText())));
        var days=new ArrayList<>(LocalDate.parse("2024-10-22").datesUntil(LocalDate.parse("2025-04-01"))
                .filter(d->special.contains(d)||d.getDayOfWeek().getValue()<=5&&!closed.contains(d)).toList());
        days.addAll(NumericalResearchExportTest.sessions());return days;
    }
    NumericalResearchExport.Input input() throws Exception {
        var days=sessions();var helper=new NumericalResearchExportTest();var items=new ArrayList<NumericalResearchExport.Instrument>();
        for(int k=1;k<=4;k++){
            var bars=new ArrayList<NumericalResearchExport.Bar>();int n=0;for(var d:days)bars.add(helper.bar(k*100000L+n++,d,100,false));
            items.add(new NumericalResearchExport.Instrument(k,"FIXTURE"+k,bars));
        }
        return new NumericalResearchExport.Input(UUID.randomUUID(),"a".repeat(64),"b".repeat(64),"c".repeat(64),days,items);
    }
    @Test void expandedCalendarAnd600RowsAreDeterministicButUncertified() throws Exception {
        var i=input();var engine=new NumericalResearchExport();var r=engine.buildExpanded(i);
        assertThat(r.version()).isEqualTo(NumericalResearchExport.EXPANDED_VERSION);assertThat(r.calendarSessionSha256()).isEqualTo(NumericalResearchExport.EXPANDED_CALENDAR_HASH);
        assertThat(r.decisionDateCount()).isEqualTo(150);assertThat(r.candidateRowCount()).isEqualTo(600);assertThat(r.completeArithmeticRowCount()).isEqualTo(600);
        assertThat(r.certifiedLabelCount()).isZero();assertThat(r.trainingAuthorized()).isFalse();assertThat(r.databaseWritesPerformed()).isFalse();
        assertThat(r.databaseQueryCount()+r.providerCallCount()+r.modelCallCount()+r.ordersCreated()).isZero();
        assertThat(r.rows().getFirst().featureSnapshot().featureFrom()).isEqualTo(LocalDate.parse("2024-10-22"));
        assertThat(r.rows().getLast().outcome().exitDate()).isEqualTo(LocalDate.parse("2026-07-06"));
        assertThat(r).isEqualTo(engine.buildExpanded(i));
    }
    @Test void profilesCannotBeConfusedOrCalendarAltered() throws Exception {
        var engine=new NumericalResearchExport();var old=new NumericalResearchExportTest().input();var expanded=input();
        assertThatThrownBy(()->engine.buildExpanded(old)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->engine.build(expanded)).isInstanceOf(IllegalArgumentException.class);
        Collections.swap(expanded.sessions(),0,1);
        assertThatThrownBy(()->engine.buildExpanded(expanded)).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void gapsAreKeptAndFuturePricesDoNotChangeFeatures() throws Exception {
        var i=input();var engine=new NumericalResearchExport();var before=engine.buildExpanded(i);
        var bars=i.instruments().getFirst().bars();int n=i.sessions().indexOf(LocalDate.parse("2026-06-08"));var old=bars.get(n);
        bars.set(n,new NumericalResearchExportTest().bar(old.candleId(),old.date(),200,false));
        var after=engine.buildExpanded(i);
        assertThat(after.rows().stream().map(NumericalResearchExport.Row::featureSnapshot).toList()).isEqualTo(before.rows().stream().map(NumericalResearchExport.Row::featureSnapshot).toList());
        assertThat(after.rows()).isNotEqualTo(before.rows());
        bars.remove(n);var gaps=engine.buildExpanded(i);
        assertThat(gaps.candidateRowCount()).isEqualTo(600);assertThat(gaps.blockedRowCount()).isPositive();
        assertThat(gaps.rows().get(149).outcome().status()).isEqualTo("MISSING_BAR");
        bars.removeFirst();assertThat(engine.buildExpanded(i).rows().getFirst().featureStatus()).isNotEqualTo("MATCHES_REVIEWED_CALENDAR");
    }
    @Test void expandedHttpAndSharedConcurrencyGuard() throws Exception {
        var controller=new NumericalResearchExportController(MAPPER);var mvc=MockMvcBuilders.standaloneSetup(controller).build();
        var url="/api/v1/training/numerical-expanded-research-export";
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(MAPPER.writeValueAsBytes(input()))).andExpect(status().isOk());
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isBadRequest());
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(new byte[2*1024*1024+1])).andExpect(status().isPayloadTooLarge());
        var first=org.mockito.Mockito.mock(jakarta.servlet.http.HttpServletRequest.class);
        var second=new org.springframework.mock.web.MockHttpServletRequest();second.setContent("{}".getBytes());
        org.mockito.Mockito.when(first.getInputStream()).thenAnswer(inv->{
            assertThatThrownBy(()->controller.exportExpanded(second)).isInstanceOf(org.springframework.web.server.ResponseStatusException.class).hasMessageContaining("429");
            throw new java.io.IOException("fixture failure");
        });
        assertThatThrownBy(()->controller.export(first)).isInstanceOf(java.io.IOException.class);
        assertThatThrownBy(()->controller.exportExpanded(second)).isInstanceOf(org.springframework.web.server.ResponseStatusException.class).hasMessageContaining("400");
    }
}
