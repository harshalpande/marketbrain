package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static in.marketbrain.training.NumericalEvaluationEngineering.*;
import static in.marketbrain.training.NumericalEvaluationEngineering.Baselines.*;
import static org.assertj.core.api.Assertions.*;

class NumericalBaselineEngineeringTest {
    List<Labeled> training() {return data("LINEAR_SIGNAL").stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList();}
    Instant cutoff(){return manifest().windows().get(Partition.VALIDATION).first().atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant();}
    Labeled changeFeatures(Labeled row,Map<String,Double> features){var m=row.metadata();var x=m.inference();return new Labeled(new EvaluationRow(new InferenceInput(x.instrument(),x.decisionAt(),x.featuresAvailableAt(),features),m.labelEndAt(),m.partition(),m.inspection()),row.target());}
    @Test void entireSyntheticBundlePassesWithoutMarketTraining() throws Exception {
        var parsed=new com.fasterxml.jackson.databind.ObjectMapper().readTree(json(smokeBundle()));
        assertThat(parsed.get("status").asText()).isEqualTo("SYNTHETIC_CHECKS_PASSED");
        assertThat(parsed.get("checkCount").asInt()).isEqualTo(13);
        assertThat(parsed.get("evaluationRegression").get("checkCount").asInt()).isEqualTo(22);
        assertThat(parsed.get("trainingAuthorized").asBoolean()).isFalse();
        assertThat(parsed.get("automaticPromotionEnabled").asBoolean()).isFalse();
        assertThat(parsed.get("scenarios").size()).isEqualTo(3);
    }
    @Test void learnedParametersUseTrainingOnlyAndImputationMeanIsObservedTrainingMean(){
        var train=training();var model=fit(train,cutoff());
        double mean=train.stream().filter(r->r.metadata().inference().features().containsKey("volumeRatio20"))
                .mapToDouble(r->r.metadata().inference().features().get("volumeRatio20")).average().orElseThrow();
        assertThat(model.means().get(1)).isCloseTo(mean,within(1e-12));
        assertThat(model.trainingRows()).isEqualTo(120);
        var shuffled=new ArrayList<>(train);Collections.shuffle(shuffled,new Random(117));
        assertThat(fit(shuffled,cutoff())).isEqualTo(model);
        var changedHeld=data("LINEAR_SIGNAL").stream().filter(r->r.metadata().partition()!=Partition.TRAIN)
                .map(r->new Labeled(r.metadata(),-1e6)).toList();
        for(var row:changedHeld)assertThat(predict(model,row.metadata().inference())).isEqualTo(predict(fit(shuffled,cutoff()),row.metadata().inference()));
    }
    @Test void fitCannotUseUnknownOrNotYetAvailableTargets(){
        var rows=training();var first=rows.getFirst();var m=first.metadata();
        assertThatThrownBy(()->fit(rows,m.labelEndAt())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(List.of(new Labeled(new EvaluationRow(m.inference(),null,m.partition(),m.inspection()),1)),cutoff())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(List.of(new Labeled(m,Double.NaN)),cutoff())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(List.of(),cutoff())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(rows,null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(Collections.nCopies(MAX_ROWS+1,first),cutoff())).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void missingCriticalAndAllMissingOptionalTrainingFeaturesReject(){
        var rows=training();
        assertThatThrownBy(()->fit(rows.stream().map(r->changeFeatures(r,Map.of("volumeRatio20",1.0))).toList(),cutoff())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->fit(rows.stream().map(r->changeFeatures(r,Map.of("return5",1.0))).toList(),cutoff())).isInstanceOf(IllegalArgumentException.class);
        var extra=changeFeatures(rows.getFirst(),Map.of("return5",1.0,"return10",2.0,"volumeRatio20",1.0));
        assertThatThrownBy(()->fit(List.of(extra),cutoff())).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void constantAndCollinearFeaturesRemainFinite(){
        var constant=training().stream().map(r->changeFeatures(r,Map.of("return5",2.0,"volumeRatio20",2.0))).toList();
        var model=fit(constant,cutoff());assertThat(model.scales()).containsExactly(1.0,1.0);assertThat(model.weights()).containsExactly(0.0,0.0);
        equalMean(model,constant);
        var correlated=training().stream().map(r->{double x=r.metadata().inference().features().get("return5");return changeFeatures(r,Map.of("return5",x,"volumeRatio20",2*x));}).toList();
        var collinear=fit(correlated,cutoff());assertThat(collinear.weights()).allMatch(Double::isFinite);
    }
    void equalMean(Model m,List<Labeled> rows){assertThat(predict(m,rows.getFirst().metadata().inference())).isCloseTo(rows.stream().mapToDouble(Labeled::target).average().orElseThrow(),within(1e-12));}
    @Test void serializedModelRoundTripPreservesPredictions() throws Exception {
        var model=fit(training(),cutoff());
        var mapper=new com.fasterxml.jackson.databind.ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());
        var restored=mapper.readValue(json(model),Model.class);
        assertThat(restored).isEqualTo(model);
        for(var row:data("LINEAR_SIGNAL"))assertThat(predict(restored,row.metadata().inference())).isEqualTo(predict(model,row.metadata().inference()));
        assertThatThrownBy(()->model.weights().set(0,999.0)).isInstanceOf(UnsupportedOperationException.class);
    }
    @Test void malformedModelAndPredictionOverflowReject(){
        var m=fit(training(),cutoff());
        assertThatThrownBy(()->new Model(m.version(),m.features(),m.means(),List.of(0.0,1.0),m.weights(),m.intercept(),m.penalty(),m.trainingRows(),m.fitCutoff(),m.trainingSha256())).isInstanceOf(IllegalArgumentException.class);
        var row=training().getFirst();var x=row.metadata().inference();
        var huge=new InferenceInput("X",x.decisionAt(),x.featuresAvailableAt(),Map.of("return5",Double.MAX_VALUE,"volumeRatio20",Double.MAX_VALUE));
        assertThatThrownBy(()->predict(m,huge)).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void rankCorrelationHandlesPerfectReverseTiesAndUnavailableDates(){
        var d=LocalDate.of(2020,1,1);var pairs=new ArrayList<Pair>();
        for(int i=0;i<3;i++)pairs.add(new Pair("S"+i,d,"R",i,-i,CONTRACT));
        var reverse=ranking(pairs);assertThat(reverse.meanSpearman()).isEqualTo(-1.0);assertThat(reverse.tieInclusiveTopMeanPercent()).isEqualTo(-2);
        pairs.add(new Pair("S",d.plusDays(1),"R",1,1,CONTRACT));
        var mix=ranking(pairs);assertThat(mix.correlationDateCount()).isEqualTo(1);assertThat(mix.unavailableCorrelationDates()).isEqualTo(1);
        Collections.reverse(pairs);assertThat(ranking(pairs)).isEqualTo(mix);
        assertThatThrownBy(()->ranking(List.of())).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void fixedManifestHasMatureChronologicalTwentySessionLabels(){
        var m=manifest();var rows=data("LINEAR_SIGNAL");
        assertThat(rows).hasSize(210);assertThat(m.horizonSessions()).isEqualTo(20);
        assertThat(guard(m,rows.stream().map(Labeled::metadata).toList()).issues()).isEmpty();
        var s=scenario("LINEAR_SIGNAL");
        for(var partition:List.of(s.validation(),s.test()))for(var comparator:partition.comparisons()){
            assertThat(comparator.predictions()).hasSize(45);assertThat(comparator.errors().dateCount()).isEqualTo(15);
        }
    }
}
