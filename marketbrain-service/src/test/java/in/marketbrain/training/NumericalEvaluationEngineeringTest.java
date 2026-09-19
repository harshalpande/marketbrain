package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static in.marketbrain.training.NumericalEvaluationEngineering.*;
import static org.assertj.core.api.Assertions.*;

class NumericalEvaluationEngineeringTest {
    @Test void standaloneFixturesPassAndProduceParseableCompactEvidence() throws Exception {
        var result = smoke();
        var parsed = new com.fasterxml.jackson.databind.ObjectMapper().readTree(json(result));
        assertThat(parsed.get("status").asText()).isEqualTo("SYNTHETIC_CHECKS_PASSED");
        assertThat(parsed.get("checkCount").asInt()).isGreaterThanOrEqualTo(22);
        assertThat(parsed.get("trainingAuthorized").asBoolean()).isFalse();
        for (var check : parsed.get("checks")) {
            assertThat(check.get("passed").asBoolean()).isTrue();
            assertThat(check.get("fixtureSha256").asText()).matches("[a-f0-9]{64}");
        }
    }
    @Test void fixtureHashesStableAcrossRuns() {
        var a = (List<Check>)smoke().get("checks"); var b = (List<Check>)smoke().get("checks");
        assertThat(a.stream().map(Check::fixtureSha256).toList()).isEqualTo(b.stream().map(Check::fixtureSha256).toList());
    }
    @Test void metricCountsAndDateWeightingAreExplicit() {
        var r = metrics(fixtureContract(), fixturePairs());
        assertThat(r.rowCount()).isEqualTo(3); assertThat(r.dateCount()).isEqualTo(2);
        assertThat(r.rowWeighted().mae()).isEqualTo(2);
        assertThat(r.equalDateWeighted().mae()).isEqualTo(2.25);
        assertThat(r.equalDateWeighted().rmse()).isEqualTo(Math.sqrt(5.75));
        assertThat(r.trainingAuthorized()).isFalse();
    }
    @Test void identifiersContractsAndUnitsAreValidated() {
        assertThatThrownBy(() -> new Contract(0, "PERCENTAGE_POINTS", "X")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new Contract(61, "PERCENTAGE_POINTS", "X")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new Contract(2, "FRACTION", "X")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new Contract(2, "PERCENTAGE_POINTS", " ")).isInstanceOf(IllegalArgumentException.class);
        Pair p = fixturePairs().getFirst();
        assertThatThrownBy(() -> metrics(fixtureContract(), List.of(new Pair("", p.decisionDate(), "X", 1, 1, p.contract())))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> metrics(fixtureContract(), List.of(new Pair("A", null, "X", 1, 1, p.contract())))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> metrics(fixtureContract(), Arrays.asList((Pair)null))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> metrics(fixtureContract(), List.of(p, new Pair("B", p.decisionDate(), "OTHER", 1, 1, p.contract())))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void observedNonFiniteAndOverflowCannotBecomeScores() {
        for (double value : new double[]{Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY}) {
            assertThatThrownBy(() -> metrics(fixtureContract(), List.of(new Pair("A", LocalDate.now(), "X", 0, value, fixtureContract())))).isInstanceOf(IllegalArgumentException.class);
        }
        var rows = List.of(new Pair("A", LocalDate.of(2020,1,1), "X", 1e154, 0, fixtureContract()), new Pair("B", LocalDate.of(2020,1,1), "X", 1e154, 0, fixtureContract()));
        assertThatThrownBy(() -> metrics(fixtureContract(), rows)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> metrics(fixtureContract(), Collections.nCopies(MAX_ROWS + 1, fixturePairs().getFirst()))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void perfectAndOppositeDirectionsAndFlatAreNotTradingAccuracy() {
        var c = fixtureContract(); var d = LocalDate.of(2020,1,1);
        var perfect = metrics(c, List.of(new Pair("A", d, "X", -1,-1,c), new Pair("B",d,"X",0,0,c)));
        assertThat(perfect.rowWeighted()).isEqualTo(new Summary(0,0,0,100));
        assertThat(metrics(c,List.of(new Pair("A",d,"X",-1,1,c))).rowWeighted().directionAgreementPercent()).isZero();
    }
    @Test void featureAllowlistAndAvailabilityFailClosed() {
        Instant t = Instant.parse("2020-01-01T10:30:00Z");
        for (String key : List.of("actualRank", "forwardReturn", "label", "unknown")) {
            assertThatThrownBy(() -> new InferenceInput("A",t,t,Map.of(key,1.0))).isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> new InferenceInput("A",null,t,Map.of("return5",1.0))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new InferenceInput("A",t,t,Map.of())).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new InferenceInput("A",t,t,Map.of("return5",Double.NaN))).isInstanceOf(IllegalArgumentException.class);
        Map<String,Double> nullable = new HashMap<>(); nullable.put("return5",null);
        assertThatThrownBy(() -> new InferenceInput("A",t,t,nullable)).isInstanceOf(IllegalArgumentException.class);
        Map<String,Double> mutable = new HashMap<>(); mutable.put("return5",1.0);
        var input = new InferenceInput("A",t,t,mutable); mutable.put("actualRank",3.0);
        assertThat(input.features()).containsOnlyKeys("return5");
    }
    @Test void missingWrongOrBackwardLabelEndFails() {
        var m = fixtureManifest(); var base = fixtureRows(m); var r = base.getFirst();
        for (Instant end : new Instant[]{null, r.inference().decisionAt(), r.labelEndAt().plusSeconds(86400)}) {
            var rows = new ArrayList<>(base); rows.set(0,new EvaluationRow(r.inference(),end,r.partition(),r.inspection()));
            assertThat(guard(m,rows).issues()).extracting(Issue::code).contains("INVALID_LABEL_END");
        }
    }
    @Test void boundaryOverlapCannotHideBehindValidHorizon() {
        var m = fixtureManifest();
        var windows = new EnumMap<>(m.windows());
        windows.put(Partition.TRAIN, new Window(m.sessions().get(0),m.sessions().get(3)));
        var manifest = new Manifest(m.sessions(),windows,2,1,m.availabilityPolicy(),List.of());
        var rows = new ArrayList<>(fixtureRows(m)); rows.set(0,fixtureRow(m,3,Partition.TRAIN));
        var result = guard(manifest,rows);
        assertThat(result.issues()).extracting(Issue::code).containsExactly("LABEL_OVERLAP_NEXT_PARTITION");
    }
    @Test void unknownOrInspectedTestRowFailsEvenWithEmptyHistory() {
        var m = fixtureManifest(); var base = fixtureRows(m); var r = base.getLast();
        for (Inspection inspection : new Inspection[]{null,Inspection.UNKNOWN,Inspection.INSPECTED}) {
            var rows = new ArrayList<>(base); rows.set(2,new EvaluationRow(r.inference(),r.labelEndAt(),r.partition(),inspection));
            assertThat(guard(m,rows).issues()).extracting(Issue::code).contains("TEST_NOT_UNTOUCHED");
        }
    }
    @Test void malformedManifestIsRejectedRatherThanReportedPassed() {
        var m = fixtureManifest(); var rows = fixtureRows(m);
        var duplicate = new ArrayList<>(m.sessions()); duplicate.set(1,duplicate.getFirst());
        var reversed = new ArrayList<>(m.sessions()); Collections.reverse(reversed);
        for (var dates : List.of(duplicate,reversed,List.<LocalDate>of())) {
            assertThatThrownBy(() -> guard(new Manifest(dates,m.windows(),2,1,m.availabilityPolicy(),List.of()),rows)).isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> guard(new Manifest(m.sessions(),Map.of(),2,1,m.availabilityPolicy(),List.of()),rows)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> guard(new Manifest(m.sessions(),m.windows(),2,1,m.availabilityPolicy(),null),rows)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> guard(new Manifest(m.sessions(),m.windows(),2,-1,m.availabilityPolicy(),List.of()),rows)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> guard(m,Collections.nCopies(MAX_ROWS+1,rows.getFirst()))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void sessionGapIsNotCalendarDayGapAndUnknownDatesFail() {
        var m = fixtureManifest(); var rows = fixtureRows(m);
        var tooLargeGap = new Manifest(m.sessions(),m.windows(),2,4,m.availabilityPolicy(),List.of());
        assertThatThrownBy(() -> guard(tooLargeGap,rows)).isInstanceOf(IllegalArgumentException.class);
        var r = rows.getFirst(); var input = r.inference();
        var unknown = new InferenceInput("A",input.decisionAt().plusSeconds(86400),input.featuresAvailableAt(),input.features());
        var changed = new ArrayList<>(rows); changed.set(0,new EvaluationRow(unknown,r.labelEndAt(),r.partition(),r.inspection()));
        assertThat(guard(m,changed).issues()).extracting(Issue::code).contains("HORIZON_UNAVAILABLE");
    }
    @Test void jsonEscapingAndCanonicalMapOrder() throws Exception {
        String sample = "quote\" slash\\ line\n tab\t control\u0001";
        assertThat(new com.fasterxml.jackson.databind.ObjectMapper().readTree(json(sample)).asText()).isEqualTo(sample);
        assertThat(json(Map.of("b",1,"a",2))).isEqualTo("{\"a\":2,\"b\":1}");
        assertThatThrownBy(() -> json(Double.NaN)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> main(new String[]{"--market-data"})).isInstanceOf(IllegalArgumentException.class);
    }
}
