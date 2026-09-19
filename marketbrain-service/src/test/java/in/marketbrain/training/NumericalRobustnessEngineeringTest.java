package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static in.marketbrain.training.NumericalEvaluationEngineering.*;
import static in.marketbrain.training.NumericalEvaluationEngineering.Robustness.*;
import static org.assertj.core.api.Assertions.*;

class NumericalRobustnessEngineeringTest {
    @Test void fullBundleIsSyntheticAndAllChecksPass() throws Exception {
        var result=new com.fasterxml.jackson.databind.ObjectMapper().readTree(json(smokeBundle()));
        assertThat(result.get("status").asText()).isEqualTo("SYNTHETIC_CHECKS_PASSED");
        assertThat(result.get("checkCount").asInt()).isEqualTo(12);
        assertThat(result.get("failedCheckCount").asInt()).isZero();
        assertThat(result.get("trainingAuthorized").asBoolean()).isFalse();
        assertThat(result.get("readiness").get("automaticPromotionEnabled").asBoolean()).isFalse();
        assertThat(result.get("readiness").get("blockers").size()).isEqualTo(5);
        assertThat(result.get("horizons").size()).isEqualTo(3);
    }
    @Test void allHorizonsUseMatureTrainingLabelsAndDisjointTestDates() {
        for(int horizon:List.of(5,20,60)) {
            var dates=new HashSet<LocalDate>();
            for(int f=0;f<3;f++) {
                var fold=fold(horizon,f);var manifest=fold.manifest();
                assertThat(fold.model().trainingRows()).isEqualTo(180+90*f);
                assertThat(fold.guard().issues()).isEmpty();
                assertThat(manifest.previouslyInspectedPeriods()).hasSize(f);
                var train=data(manifest).stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList();
                assertThat(train).allMatch(r->r.metadata().labelEndAt().isBefore(fold.model().fitCutoff()));
                for(var d:fold.test().comparisons().getFirst().predictions().stream().map(Pair::decisionDate).distinct().toList())assertThat(dates.add(d)).isTrue();
                assertThat(fold.test().comparisons()).allMatch(c->c.predictions().size()==30);
            }
            assertThat(dates).hasSize(30);
        }
    }
    @Test void mutatedHeldoutLabelsAndFeaturesDoNotInfluenceTrainingParameters() {
        var fold=fold(20,1);var rows=data(fold.manifest());
        var altered=rows.stream().map(r->{
            if(r.metadata().partition()==Partition.TRAIN)return r;
            var m=r.metadata();var x=m.inference();
            return new Baselines.Labeled(new EvaluationRow(new InferenceInput(x.instrument(),x.decisionAt(),x.featuresAvailableAt(),
                    Map.of("return5",9999.0,"volumeRatio20",9999.0)),m.labelEndAt(),m.partition(),m.inspection()),-9999);
        }).toList();
        var refit=Baselines.fit(altered.stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList(),fold.model().fitCutoff());
        assertThat(refit).isEqualTo(fold.model());
    }
    @Test void costsHaveExplicitUnitsStrictThresholdAndEqualDateWeighting() {
        var c=new Contract(5,"PERCENTAGE_POINTS","SYNTHETIC_ONLY");var d=LocalDate.of(2020,1,1);
        var rows=List.of(new Pair("A",d,"X",2,1,c),new Pair("B",d,"X",0.25,-2,c),new Pair("A",d.plusDays(1),"X",3,4,c));
        var measured=costs(c,rows,25);
        assertThat(measured.selectedCount()).isEqualTo(2);
        assertThat(measured.coveragePercent()).isCloseTo(200.0/3,within(1e-10));
        assertThat(measured.meanSelectedNetPercent()).isEqualTo(2.25);
        assertThat(measured.equalDateMeanContributionPercent()).isEqualTo(2.0625);
        var reversed=new ArrayList<>(rows);Collections.reverse(reversed);assertThat(costs(c,reversed,25)).isEqualTo(measured);
    }
    @Test void costsRejectInvalidContractDuplicatesOverflowAndEmpty() {
        var c=new Contract(5,"PERCENTAGE_POINTS","SYNTHETIC_ONLY");var d=LocalDate.of(2020,1,1);
        var row=new Pair("A",d,"X",2,1,c);
        assertThatThrownBy(()->costs(c,List.of(),0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->costs(c,List.of(row),-1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->costs(c,List.of(row),10_001)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->costs(c,List.of(row,row),0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->costs(new Contract(20,"PERCENTAGE_POINTS","SYNTHETIC_ONLY"),List.of(row),0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->costs(c,List.of(new Pair("A",d,"X",Double.MAX_VALUE,0,c)),0)).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void zeroAndNegativePredictionsAbstainWithoutInventingSuccess() {
        var c=new Contract(5,"PERCENTAGE_POINTS","SYNTHETIC_ONLY");var d=LocalDate.of(2020,1,1);
        var r=costs(c,List.of(new Pair("A",d,"X",0,10,c),new Pair("B",d,"X",-1,-2,c)),0);
        assertThat(r.selectedCount()).isZero();assertThat(r.meanSelectedNetPercent()).isNull();assertThat(r.equalDateMeanContributionPercent()).isZero();
    }
    @Test void noBestFoldCherryPickingAndMixedPoolsRejected() {
        var h=horizon(20);assertThat(h.folds()).hasSize(3);
        for(var c:h.pooledTest()) {
            assertThat(c.errors().rowCount()).isEqualTo(90);assertThat(c.errors().dateCount()).isEqualTo(30);
            double mean=h.folds().stream().flatMap(f->f.test().comparisons().stream()).filter(p->p.predictor().equals(c.predictor()))
                    .mapToDouble(p->p.errors().equalDateWeighted().mae()).average().orElseThrow();
            assertThat(c.errors().equalDateWeighted().mae()).isCloseTo(mean,within(1e-10));
        }
        assertThatThrownBy(()->aggregate(h.folds().getFirst().contract(),List.of(h.folds().getFirst(),h.folds().getFirst(),h.folds().getLast()))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->aggregate(new Contract(5,"PERCENTAGE_POINTS","SYNTHETIC_ONLY"),h.folds())).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void inspectedFinalWindowAndBoundaryLeakStillReject() {
        var m=manifest(60,0);var rows=data(m).stream().map(Baselines.Labeled::metadata).toList();
        var inspected=new Manifest(m.sessions(),m.windows(),60,5,m.availabilityPolicy(),List.of(m.windows().get(Partition.TEST)));
        assertThat(guard(inspected,rows).issues()).anyMatch(i->i.code().equals("TEST_NOT_UNTOUCHED"));
        var changed=new ArrayList<>(rows);var first=rows.getFirst();
        changed.set(0,new EvaluationRow(first.inference(),m.windows().get(Partition.VALIDATION).first().atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant(),Partition.TRAIN,Inspection.UNINSPECTED));
        assertThat(guard(m,changed).issues()).anyMatch(i->i.code().equals("LABEL_OVERLAP_NEXT_PARTITION"));
    }
    @Test void unsupportedFixtureConfigurationsReject() {
        assertThatThrownBy(()->manifest(10,0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->manifest(20,-1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->manifest(20,3)).isInstanceOf(IllegalArgumentException.class);
    }
}
