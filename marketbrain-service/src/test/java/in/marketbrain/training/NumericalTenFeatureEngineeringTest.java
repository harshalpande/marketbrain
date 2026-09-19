package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import static in.marketbrain.training.NumericalTenFeatureEngineering.*;
import static org.assertj.core.api.Assertions.*;

class NumericalTenFeatureEngineeringTest {
    @Test void completeEmbeddedSuitePasses() {
        var r=suite("test-revision");assertThat(r.get("status")).isEqualTo("SYNTHETIC_CHECKS_PASSED");
        assertThat(r.get("checkCount")).isEqualTo(32);assertThat(r.get("failedCheckCount")).isEqualTo(0L);
        assertThat(r.get("realMarketTrainingAuthorized")).isEqualTo(false);
    }
    @Test void featureContractAndPinnedHashMatchRepository() throws Exception {
        assertThat(FEATURES).containsExactlyElementsOf(NumericalDataContract.draft().candidateFeatures());
        var root=Path.of(System.getProperty("user.dir"));if(!Files.exists(root.resolve("ops/data")))root=root.getParent();
        String contract=Files.readString(root.resolve("ops/data/numerical-prefit-contract-v1.json")).replace("\r\n","\n");
        assertThat(sha(contract)).isEqualTo(CONTRACT_SHA);
    }
    // Independent closed-form ridge oracle: balanced +/-1 design, one active column.
    // Ridge shrinkage is expected; asserting perfect target recovery would be incorrect.
    List<Row> oracleRows(Manifest m, boolean collinear) {
        var result=new ArrayList<Row>();
        for(var p:Partition.values()) for(int stock=0;stock<2;stock++) {
            var d=m.windows().get(p).first();var t=instant(d);int end=m.sessions().indexOf(d)+20;
            var f=new LinkedHashMap<String,Double>();FEATURES.forEach(name->f.put(name,0.0));double x=stock==0?-1:1;
            f.put(FEATURES.get(0),x);if(collinear)f.put(FEATURES.get(1),x);
            result.add(new Row(new Input("S"+stock,t,t.minusSeconds(1),f),3+2*x,instant(m.sessions().get(end)),instant(m.sessions().get(end)),p,true,POLICY));
        }return result;
    }
    @Test void wholePipelineMatchesIndependentOneDimensionalOracle() {
        var m=fixtureManifest(0);var rows=oracleRows(m,false);var model=fit(m,rows,"oracle");
        assertThat(model.means().get(0)).isEqualTo(0);assertThat(model.scales().get(0)).isEqualTo(1);
        assertThat(model.intercept()).isEqualTo(3);assertThat(model.coefficients().get(0)).isCloseTo(2/1.01,within(1e-12));
        var i=rows.getLast().input();assertThat(predict(model,i)).isCloseTo(3+2/1.01,within(1e-12));
        assertThat(model.coefficients().subList(1,10)).containsOnly(0.0);
    }
    @Test void collinearWholePipelineMatchesIndependentClosedForm() {
        var m=fixtureManifest(0);var model=fit(m,oracleRows(m,true),"oracle");
        assertThat(model.coefficients().get(0)).isCloseTo(2/2.01,within(1e-12));
        assertThat(model.coefficients().get(1)).isCloseTo(2/2.01,within(1e-12));
    }
    @Test void unequalDateCountsHaveHandCalculatedMeanAndVariance() {
        var m=fixtureManifest(0);var rows=new ArrayList<>(oracleRows(m,false));var source=rows.getFirst();
        var f=new LinkedHashMap<>(source.input().features());f.put(FEATURES.get(0),4.0);var t=source.input().decisionAt().plusSeconds(86400);
        rows.add(new Row(new Input("OTHER",t,t,f),9.0,source.labelEnd().plusSeconds(86400),source.labelAvailable().plusSeconds(86400),Partition.TRAIN,true,POLICY));
        var model=fit(m,rows,"oracle");assertThat(model.means().get(0)).isEqualTo(2);
        assertThat(model.scales().get(0)).isCloseTo(Math.sqrt(4.5),within(1e-12));assertThat(model.trainingMean()).isEqualTo(6);
    }
    @Test void targetAndFeatureMutationCannotAlterFittedParameters() {
        var m=fixtureManifest(0);var rows=fixture(m,"LINEAR");var fitted=fit(m,rows,"r");
        var bad=rows.stream().map(r->r.partition()==Partition.TRAIN?r:replace(r,r.input(),-999.0,r.labelEnd(),r.labelAvailable(),POLICY)).toList();
        assertThat(fit(m,bad,"r")).isEqualTo(fitted);
    }
    @Test void missingWholePartitionFailsRatherThanManufacturingSuccess() {
        var m=fixtureManifest(0);var rows=fixture(m,"LINEAR").stream().filter(r->r.partition()!=Partition.TEST).toList();
        assertThatThrownBy(()->prepare(m,rows)).hasMessageContaining("EMPTY_ELIGIBLE_TEST");
    }
    @Test void everyMarketRowIsRejectedWithoutAnOverride() {
        var m=fixtureManifest(0);var rows=fixture(m,"LINEAR").stream().map(r->replace(r,r.input(),r.target(),r.labelEnd(),r.labelAvailable(),"CERTIFIED_MARKET")).toList();
        assertThatThrownBy(()->fit(m,rows,"r")).hasMessageContaining("EMPTY_ELIGIBLE_TRAIN");
        assertThatThrownBy(()->main(new String[]{"--market-fit","some-file"})).hasMessageContaining("ONLY_FIXED_SYNTHETIC");
    }
    @Test void overflowingFeaturesFailClosedWithoutChangingAlpha() {
        var m=fixtureManifest(0);var rows=new ArrayList<>(oracleRows(m,false));var r=rows.getFirst();var f=new LinkedHashMap<>(r.input().features());f.put(FEATURES.get(0),Double.MAX_VALUE);
        rows.set(0,replace(r,new Input(r.input().instrument(),r.input().decisionAt(),r.input().availableAt(),f),r.target(),r.labelEnd(),r.labelAvailable(),POLICY));
        assertThatThrownBy(()->fit(m,rows,"r")).hasMessageContaining("OVERFLOW");assertThat(ALPHA).isEqualTo(0.01);
    }
    @Test void sameDatePartitionEscapeAndInspectedRowReject() {
        var m=fixtureManifest(0);var rows=new ArrayList<>(fixture(m,"LINEAR"));var r=rows.getFirst();
        rows.set(0,new Row(r.input(),r.target(),r.labelEnd(),r.labelAvailable(),Partition.VALIDATION,true,POLICY));
        assertThatThrownBy(()->prepare(m,rows)).hasMessageContaining("ROW_OUTSIDE_PARTITION");
        assertThatThrownBy(()->prepare(new Manifest(m.sessions(),m.windows(),List.of(),true,20),fixture(m,"LINEAR"))).hasMessageContaining("INSPECTED_FINAL_TEST");
    }
    @Test void bothTemporalBoundariesAndExactEqualityArePurged() {
        var m=fixtureManifest(0);
        for(var p:List.of(Partition.TRAIN,Partition.VALIDATION)) {
            var rows=new ArrayList<>(fixture(m,"LINEAR"));int idx=0;while(rows.get(idx).partition()!=p)idx++;var r=rows.get(idx);
            var next=p==Partition.TRAIN?Partition.VALIDATION:Partition.TEST;var boundary=instant(m.windows().get(next).first());
            rows.set(idx,replace(r,r.input(),r.target(),r.labelEnd(),boundary,POLICY));
            assertThat(prepare(m,rows).excluded()).extracting(Exclusion::reason).containsExactly("PURGED_LABEL_OVERLAP");
        }
    }
    @Test void artifactRejectsUnknownFeaturesAndPoliciesEvenWithRecomputedChecksum() {
        var m=fit(fixtureManifest(0),fixture(fixtureManifest(0),"LINEAR"),"r");var wrong=new ArrayList<>(m.featureOrder());Collections.swap(wrong,0,1);
        assertThatThrownBy(()->encode(new Model(m.version(),wrong,m.featureUnits(),m.means(),m.scales(),m.constants(),m.coefficients(),m.intercept(),m.trainingMean(),m.alpha(),m.metadata()))).hasMessageContaining("SCHEMA");
        var metadata=new TreeMap<>(m.metadata());metadata.put("dataScope","MARKET");
        assertThatThrownBy(()->encode(new Model(m.version(),m.featureOrder(),m.featureUnits(),m.means(),m.scales(),m.constants(),m.coefficients(),m.intercept(),m.trainingMean(),m.alpha(),metadata))).hasMessageContaining("POLICY");
        assertThatThrownBy(()->decode(encode(m)+"extra",m.metadata())).hasMessageContaining("CHECKSUM");
    }
    @Test void featureMapsAndArtifactListsAreImmutable() {
        var f=fixtureFeatures(1,1);var t=Instant.now();var input=new Input("S",t,t,f);f.clear();assertThat(input.features()).hasSize(10);
        assertThatThrownBy(()->input.features().clear()).isInstanceOf(UnsupportedOperationException.class);
        var m=fit(fixtureManifest(0),fixture(fixtureManifest(0),"LINEAR"),"r");assertThatThrownBy(()->m.means().set(0,2.0)).isInstanceOf(UnsupportedOperationException.class);
    }
    @Test void rankTiesAndNoCrossSectionHaveExplicitSemantics() {
        var t=Instant.now();assertThat(correlation(List.of(new Prediction("S",t,1,1)))).isNull();
        assertThat(correlation(List.of(new Prediction("S",t,1,1),new Prediction("T",t,2,1)))).isNull();
        assertThat(correlation(List.of(new Prediction("S",t,1,2),new Prediction("T",t,2,1)))).isEqualTo(-1);
    }
    @Test void scenarioComparisonsPreserveLossesCostsAndCommonPopulation() {
        var fold=runFold("REVERSAL",2,"r");var e=fold.test();assertThat(e.comparisons()).hasSize(3);
        assertThat(e.comparisons().get(2).maeImprovementVsZeroPercent()).isNegative();
        for(var c:e.comparisons()){assertThat(c.predictions()).hasSize(e.evaluatedRows());assertThat(c.hypotheticalCosts()).extracting(Cost::roundTripBps).containsExactly(0,25,50,100);}
        assertThat(e.comparisons().getFirst().hypotheticalCosts()).allMatch(c->c.selectedCount()==0 && c.meanSelectedNetPercent()==null);
    }
    @Test void artifactSurvivesActualDiskRoundTrip(@org.junit.jupiter.api.io.TempDir Path dir) throws Exception {
        var m=fixtureManifest(0);var rows=fixture(m,"LINEAR");var fitted=fit(m,rows,"r");var path=dir.resolve("synthetic-model.txt");
        Files.writeString(path,encode(fitted),StandardOpenOption.CREATE_NEW);var reloaded=decode(Files.readString(path),fitted.metadata());
        for(var r:rows)if(r.partition()!=Partition.TRAIN)assertThat(predict(reloaded,r.input())).isEqualTo(predict(fitted,r.input()));
    }
    @Test void blockResamplingIsBoundedPairedAndOrderInvariant() {
        var f=runFold("LINEAR",0,"r");var b=f.test().comparisons().get(0).predictions();var c=f.test().comparisons().get(2).predictions();
        var reverse=new ArrayList<>(c);Collections.reverse(reverse);
        assertThat(uncertainty(b,c,2,200,42,0.95)).isEqualTo(uncertainty(b,reverse,2,200,42,0.95));
        assertThatThrownBy(()->uncertainty(b,c,9,200,42,0.95)).hasMessageContaining("BLOCK");
        assertThatThrownBy(()->uncertainty(b,c,2,10000,42,0.95)).hasMessageContaining("PARAMETERS");
        var changed=new ArrayList<>(c);var p=changed.getFirst();changed.set(0,new Prediction(p.instrument(),p.decisionAt(),999,p.predicted()));
        assertThatThrownBy(()->uncertainty(b,changed,2,200,42,0.95)).hasMessageContaining("UNPAIRED");
    }
}
