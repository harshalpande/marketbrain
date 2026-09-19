package in.marketbrain.training;

import in.marketbrain.feature.FeatureValues;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import static in.marketbrain.training.NumericalResearchExportTest.MAPPER;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalResearchMappingTest {
    private BigDecimal n(String value) { return new BigDecimal(value); }
    private FeatureValues features(String sma, String rsi) {
        return new FeatureValues(n("99"),n("2"),n(sma),n("80"),n("50"),n("105"),n("100"),n(rsi),n("3"),n("20"),n("1.2"),n("75"));
    }
    @Test void mapsExactTenFeaturesWithUnitsAndNoOutcomeFields() throws Exception {
        var v=NumericalResearchMapping.map(features("100","60"),n("110"));
        assertThat(v.closeToSma20Percent()).isEqualByComparingTo("10");
        assertThat(v.closeToSma50Percent()).isEqualByComparingTo("37.5");
        assertThat(v.closeToSma200Percent()).isEqualByComparingTo("120");
        assertThat(v.ema12ToEma26Percent()).isEqualByComparingTo("5");
        assertThat(v.atr14ToClosePercent()).isEqualByComparingTo("2.72727273");
        assertThat(v.dailyReturnPercent()).isEqualByComparingTo("2");
        var json=MAPPER.valueToTree(v);assertThat(json.size()).isEqualTo(10);
        assertThat(MAPPER.writeValueAsString(v)).doesNotContain("outcome","actualRank","return5","instrumentId");
        for(var name:NumericalDataContract.draft().candidateFeatures())assertThat(json.has(name)).isTrue();
    }
    @Test void rejectsMissingAndInvalidNumericInputs() {
        assertThatThrownBy(()->NumericalResearchMapping.map(null,n("10"))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->NumericalResearchMapping.map(features("0","50"),n("10"))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->NumericalResearchMapping.map(features("100","101"),n("10"))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->NumericalResearchMapping.map(features("100","50"),n("0"))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void allRowsAndDateGroupsRetainedWithoutTrainingAuthorization() throws Exception {
        var r=new NumericalResearchMapping().build(new NumericalExpandedResearchTest().input());
        assertThat(r.rowCount()).isEqualTo(600);assertThat(r.mappingReadyCount()).isEqualTo(600);
        assertThat(r.dateCoverage()).hasSize(150);assertThat(r.dateCoverage()).allSatisfy(d->{assertThat(d.rowCount()).isEqualTo(4);assertThat(d.trainingEligibleCount()).isZero();});
        assertThat(r.rows()).allSatisfy(row->{assertThat(row.trainingEligible()).isFalse();assertThat(row.blockers()).containsAll(NumericalResearchMapping.GATES);});
        assertThat(r.rows().getFirst().proposedCutoff()).isEqualTo(Instant.parse("2025-10-27T10:30:00Z"));
        assertThat(r.trainingEligibleCount()+r.certifiedLabelCount()+r.databaseQueryCount()+r.providerCallCount()+r.modelCallCount()+r.ordersCreated()).isZero();
        assertThat(r.trainingAuthorized()).isFalse();assertThat(r.databaseWritesPerformed()).isFalse();
    }
    @Test void futurePriceMutationCannotChangeVectorsOrEligibility() throws Exception {
        var input=new NumericalExpandedResearchTest().input();var builder=new NumericalResearchMapping();var before=builder.build(input);
        var bars=input.instruments().getFirst().bars();var d=LocalDate.parse("2026-06-08");int index=input.sessions().indexOf(d);
        bars.set(index,new NumericalResearchExportTest().bar(bars.get(index).candleId(),d,200,false));
        assertThat(builder.build(input)).isEqualTo(before);
    }
    @Test void excludedOrMissingFeatureWindowsRemainInLedger() throws Exception {
        var input=new NumericalExpandedResearchTest().input();var bars=input.instruments().getFirst().bars();var first=bars.getFirst();
        bars.set(0,new NumericalResearchExportTest().bar(first.candleId(),first.date(),100,true));
        var r=new NumericalResearchMapping().build(input);
        assertThat(r.rowCount()).isEqualTo(600);assertThat(r.mappingReadyCount()).isLessThan(600);
        assertThat(r.rows().getFirst().features()).isNull();assertThat(r.rows().getFirst().blockers()).contains("FEATURE_WINDOW_INVALID");
        bars.removeFirst();assertThat(new NumericalResearchMapping().build(input).rowCount()).isEqualTo(600);
    }
    @Test void earlyOrMissingReceiptsCannotCertifyHistoricalAvailability() throws Exception {
        var input=new NumericalExpandedResearchTest().input();var bars=input.instruments().getFirst().bars();
        for(int i=0;i<bars.size();i++) {var b=bars.get(i);bars.set(i,new NumericalResearchExport.Bar(b.candleId(),b.date(),b.source(),null,b.open(),b.high(),b.low(),b.close(),b.volume(),b.excluded()));}
        var r=new NumericalResearchMapping().build(input);
        assertThat(r.rows().getFirst().missingReceivedAtCount()).isEqualTo(252);
        assertThat(r.rows().getFirst().blockers()).contains("STORED_RECEIPT_MISSING","HISTORICAL_AVAILABILITY_UNVERIFIED");
        assertThat(r.trainingEligibleCount()).isZero();
        for(int i=0;i<bars.size();i++) {var b=bars.get(i);bars.set(i,new NumericalResearchExport.Bar(b.candleId(),b.date(),b.source(),Instant.parse("2024-01-01T00:00:00Z"),b.open(),b.high(),b.low(),b.close(),b.volume(),b.excluded()));}
        var early=new NumericalResearchMapping().build(input);
        assertThat(early.rows().getFirst().receivedAfterCutoffCount()).isZero();
        assertThat(early.rows().getFirst().blockers()).contains("HISTORICAL_AVAILABILITY_UNVERIFIED").doesNotContain("STORED_RECEIPT_AFTER_CUTOFF","STORED_RECEIPT_MISSING");
        assertThat(early.trainingEligibleCount()).isZero();
    }
    @Test void endpointBoundsAndSharedSlotAreEnforcedAndReleased() throws Exception {
        var controller=new NumericalResearchExportController(MAPPER);var mvc=MockMvcBuilders.standaloneSetup(controller).build();
        var url="/api/v1/training/numerical-research-mapping";
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isBadRequest());
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(new byte[2*1024*1024+1])).andExpect(status().isPayloadTooLarge());
        mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(MAPPER.writeValueAsBytes(new NumericalExpandedResearchTest().input()))).andExpect(status().isOk());
        var first=org.mockito.Mockito.mock(jakarta.servlet.http.HttpServletRequest.class);
        var second=new org.springframework.mock.web.MockHttpServletRequest();second.setContent("{}".getBytes());
        org.mockito.Mockito.when(first.getInputStream()).thenAnswer(inv->{
            assertThatThrownBy(()->controller.mapping(second)).hasMessageContaining("429");
            throw new java.io.IOException("fixture");
        });
        assertThatThrownBy(()->controller.exportExpanded(first)).isInstanceOf(java.io.IOException.class);
        assertThatThrownBy(()->controller.mapping(second)).hasMessageContaining("400");
    }
}
