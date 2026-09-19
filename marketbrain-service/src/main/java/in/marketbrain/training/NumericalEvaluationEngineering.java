package in.marketbrain.training;

import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** Standalone JDK-only evaluation engineering, with a synthetic-only baseline lab.
 * No Spring bean or data source. main accepts only fixed synthetic fixture suites.
 */
public final class NumericalEvaluationEngineering {
    public static final String VERSION = "NUMERICAL_EVALUATION_ENGINEERING_V1";
    public static final int MAX_ROWS = 10_000;
    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");
    private static final Set<String> FEATURES = Set.of("return5", "return10", "return20", "volatility20", "volumeRatio20");
    public record Contract(int horizonSessions, String unit, String pricePolicy) {
        public Contract {
            require(horizonSessions > 0 && horizonSessions <= 60, "Invalid horizon");
            require("PERCENTAGE_POINTS".equals(unit), "Expected percentage-point returns");
            identifier(pricePolicy);
        }
    }
    public record Pair(String instrument, LocalDate decisionDate, String predictionId,
                       double predicted, double observed, Contract contract) { }
    public record Summary(double mae, double rmse, double signedBias, double directionAgreementPercent) { }
    public record Metrics(String status, int rowCount, int dateCount, Contract contract,
                          Summary rowWeighted, Summary equalDateWeighted) {
        public boolean trainingAuthorized() { return false; }
    }
    private record Key(String predictionId, String instrument, LocalDate date) { }

    public static Metrics metrics(Contract contract, List<Pair> input) {
        require(contract != null, "Missing contract");
        require(input != null && input.size() <= MAX_ROWS, "Invalid row collection");
        var keys = new HashSet<Key>();
        String predictionId = null;
        for (Pair row : input) {
            require(row != null && row.decisionDate() != null, "Missing row/date");
            identifier(row.instrument()); identifier(row.predictionId());
            require(contract.equals(row.contract()), "Mixed contracts");
            finite(row.predicted()); finite(row.observed());
            require(keys.add(new Key(row.predictionId(), row.instrument(), row.decisionDate())), "Duplicate prediction");
            if (predictionId == null) predictionId = row.predictionId();
            require(predictionId.equals(row.predictionId()), "Evaluate each predictor separately");
        }
        if (input.isEmpty()) return new Metrics("EMPTY_UNAVAILABLE", 0, 0, contract, null, null);
        var rows = new ArrayList<>(input);
        rows.sort(Comparator.comparing(Pair::decisionDate).thenComparing(Pair::instrument));
        var dates = new TreeMap<LocalDate, Accumulator>();
        var all = new Accumulator();
        for (Pair row : rows) {
            double error = finite(row.predicted() - row.observed());
            double square = finite(error * error);
            double correct = sign(row.predicted()) == sign(row.observed()) ? 1 : 0;
            all.add(Math.abs(error), square, error, correct);
            dates.computeIfAbsent(row.decisionDate(), ignored -> new Accumulator()).add(Math.abs(error), square, error, correct);
        }
        var byDate = new Accumulator();
        for (Accumulator date : dates.values()) {
            byDate.add(date.absolute / date.count, date.square / date.count, date.signed / date.count, date.correct / date.count);
        }
        return new Metrics("METRICS_ONLY", rows.size(), dates.size(), contract, all.summary(), byDate.summary());
    }
    private static int sign(double value) { return value == 0 ? 0 : value > 0 ? 1 : -1; }
    private static final class Accumulator {
        double absolute, square, signed, correct; int count;
        void add(double a, double q, double s, double c) {
            absolute = finite(absolute + a); square = finite(square + q);
            signed = finite(signed + s); correct = finite(correct + c); count++;
        }
        Summary summary() { return new Summary(absolute / count, Math.sqrt(square / count), signed / count, 100 * correct / count); }
    }

    public enum Partition { TRAIN, VALIDATION, TEST }
    public enum Inspection { UNINSPECTED, INSPECTED, UNKNOWN }
    public record Window(LocalDate first, LocalDate last) { }
    public record Manifest(List<LocalDate> sessions, Map<Partition, Window> windows,
                           int horizonSessions, int gapSessions, String availabilityPolicy,
                           List<Window> previouslyInspectedPeriods) { }
    // Observed returns/ranks have no place in this inference DTO. An explicit allowlist
    // prevents hiding hindsight data under additional feature names.
    public record InferenceInput(String instrument, Instant decisionAt, Instant featuresAvailableAt,
                                 Map<String, Double> features) {
        public InferenceInput {
            identifier(instrument);
            require(decisionAt != null && featuresAvailableAt != null, "Unknown feature availability");
            require(!featuresAvailableAt.isAfter(decisionAt), "Future feature availability");
            require(features != null && !features.isEmpty() && FEATURES.containsAll(features.keySet()), "Unknown/empty feature set");
            for (Double value : features.values()) { require(value != null, "Missing feature"); finite(value); }
            features = Map.copyOf(features);
        }
    }
    public record EvaluationRow(InferenceInput inference, Instant labelEndAt, Partition partition, Inspection inspection) { }
    public record Issue(String instrument, LocalDate decisionDate, String code) { }
    public record GuardResult(String status, int rowCount, int dateCount, List<Issue> issues) {
        public boolean trainingAuthorized() { return false; }
    }

    public static GuardResult guard(Manifest manifest, List<EvaluationRow> rows) {
        require(manifest != null && rows != null && rows.size() <= MAX_ROWS, "Invalid manifest/rows");
        identifier(manifest.availabilityPolicy());
        require(manifest.horizonSessions() > 0 && manifest.horizonSessions() <= 60 && manifest.gapSessions() >= 0
                && manifest.gapSessions() <= 60, "Invalid horizon/gap");
        require(manifest.sessions() != null && !manifest.sessions().isEmpty() && manifest.sessions().size() <= MAX_ROWS, "Invalid calendar");
        Map<LocalDate, Integer> index = new HashMap<>();
        LocalDate previous = null;
        for (LocalDate date : manifest.sessions()) {
            require(date != null && (previous == null || date.isAfter(previous)), "Calendar must be strictly increasing");
            index.put(date, index.size()); previous = date;
        }
        require(manifest.windows() != null && manifest.windows().size() == 3, "Three partition windows required");
        Window prior = null;
        for (Partition partition : Partition.values()) {
            Window window = manifest.windows().get(partition);
            require(validWindow(window) && index.containsKey(window.first()) && index.containsKey(window.last()), "Window outside calendar");
            if (prior != null) require(index.get(window.first()) - index.get(prior.last()) - 1 >= manifest.gapSessions(), "Unordered partitions or insufficient session gap");
            prior = window;
        }
        require(manifest.previouslyInspectedPeriods() != null && manifest.previouslyInspectedPeriods().size() <= MAX_ROWS, "Inspection history must be explicit");
        for (Window window : manifest.previouslyInspectedPeriods()) require(validWindow(window), "Invalid inspected period");
        var issues = new ArrayList<Issue>();
        var identities = new HashSet<String>();
        var datePartitions = new HashMap<LocalDate, Partition>();
        var populated = EnumSet.noneOf(Partition.class);
        for (EvaluationRow row : rows) {
            require(row != null && row.inference() != null && row.partition() != null, "Missing evaluation row");
            InferenceInput input = row.inference();
            LocalDate date = input.decisionAt().atZone(INDIA).toLocalDate();
            String symbol = input.instrument();
            if (!identities.add(symbol + ":" + date)) issues.add(new Issue(symbol, date, "DUPLICATE_ROW"));
            Partition old = datePartitions.putIfAbsent(date, row.partition());
            if (old != null && old != row.partition()) issues.add(new Issue(symbol, date, "DATE_CROSSES_PARTITIONS"));
            populated.add(row.partition());
            if (!inside(date, manifest.windows().get(row.partition()))) issues.add(new Issue(symbol, date, "OUTSIDE_PARTITION"));
            Integer start = index.get(date);
            if (start == null || start + manifest.horizonSessions() >= manifest.sessions().size()) {
                issues.add(new Issue(symbol, date, "HORIZON_UNAVAILABLE"));
            } else if (row.labelEndAt() == null || !row.labelEndAt().isAfter(input.decisionAt())
                    || !row.labelEndAt().atZone(INDIA).toLocalDate().equals(manifest.sessions().get(start + manifest.horizonSessions()))) {
                issues.add(new Issue(symbol, date, "INVALID_LABEL_END"));
            }
            if (row.partition() != Partition.TEST && row.labelEndAt() != null) {
                Partition next = row.partition() == Partition.TRAIN ? Partition.VALIDATION : Partition.TEST;
                Instant boundary = manifest.windows().get(next).first().atStartOfDay(INDIA).toInstant();
                if (!row.labelEndAt().isBefore(boundary)) issues.add(new Issue(symbol, date, "LABEL_OVERLAP_NEXT_PARTITION"));
            }
            if (row.partition() == Partition.TEST && (row.inspection() != Inspection.UNINSPECTED
                    || manifest.previouslyInspectedPeriods().stream().anyMatch(w -> inside(date, w)))) {
                issues.add(new Issue(symbol, date, "TEST_NOT_UNTOUCHED"));
            }
        }
        for (Partition partition : Partition.values()) if (!populated.contains(partition)) issues.add(new Issue("", null, "EMPTY_" + partition));
        issues.sort(Comparator.comparing(Issue::decisionDate, Comparator.nullsFirst(Comparator.naturalOrder()))
                .thenComparing(Issue::instrument).thenComparing(Issue::code));
        return new GuardResult(issues.isEmpty() ? "DECLARED_METADATA_CHECKS_PASS" : "REJECTED", rows.size(), datePartitions.size(), List.copyOf(issues));
    }
    private static boolean validWindow(Window w) { return w != null && w.first() != null && w.last() != null && !w.last().isBefore(w.first()); }
    private static boolean inside(LocalDate date, Window w) { return !date.isBefore(w.first()) && !date.isAfter(w.last()); }
    private static void identifier(String value) { require(value != null && value.matches("[A-Za-z0-9_.-]{1,120}"), "Invalid identifier"); }
    private static double finite(double value) { require(Double.isFinite(value), "Non-finite value or numerical overflow"); return value; }
    private static void require(boolean condition, String message) { if (!condition) throw new IllegalArgumentException(message); }

    public record Check(String name, String fixtureSha256, boolean passed, double elapsedMillis, String failure) { }
    private static void check(List<Check> checks, String name, Object fixture, Runnable assertion) {
        long start = System.nanoTime(); String failure = null;
        try { assertion.run(); } catch (RuntimeException | AssertionError error) { failure = error.getClass().getSimpleName() + ": " + error.getMessage(); }
        checks.add(new Check(name, sha256(json(fixture)), failure == null, (System.nanoTime() - start) / 1_000_000.0, failure));
        System.err.println("CHECK " + checks.size() + " " + name + " " + (failure == null ? "PASS" : "FAIL"));
    }
    private static void equal(double actual, double expected) { if (Math.abs(actual - expected) > 1e-10 || !Double.isFinite(actual)) throw new AssertionError("Expected " + expected + ", got " + actual); }
    private static void rejects(Runnable action) { try { action.run(); } catch (IllegalArgumentException expected) { return; } throw new AssertionError("Unsafe input accepted"); }
    static Contract fixtureContract() { return new Contract(2, "PERCENTAGE_POINTS", "SYNTHETIC_ONLY"); }
    static List<Pair> fixturePairs() {
        Contract c = fixtureContract(); LocalDate d = LocalDate.of(2020, 1, 1);
        return List.of(new Pair("A", d, "FIXED", 2, 1, c), new Pair("B", d, "FIXED", -1, 1, c), new Pair("A", d.plusDays(1), "FIXED", 0, -3, c));
    }
    static Manifest fixtureManifest() {
        // Deliberately synthetic: these are not exchange sessions or production splits.
        List<LocalDate> dates = new ArrayList<>(); for (int i = 0; i < 15; i++) dates.add(LocalDate.of(2020, 1, 1).plusDays(i * 2L));
        return new Manifest(List.copyOf(dates), Map.of(Partition.TRAIN, new Window(dates.get(0), dates.get(1)),
                Partition.VALIDATION, new Window(dates.get(5), dates.get(6)), Partition.TEST, new Window(dates.get(10), dates.get(11))),
                2, 1, "SYNTHETIC_KNOWN_AVAILABILITY", List.of());
    }
    static EvaluationRow fixtureRow(Manifest m, int index, Partition partition) {
        Instant decision = m.sessions().get(index).atTime(16, 0).atZone(INDIA).toInstant();
        return new EvaluationRow(new InferenceInput("A", decision, decision.minusSeconds(1), Map.of("return5", 1.0)),
                m.sessions().get(index + m.horizonSessions()).atTime(15, 30).atZone(INDIA).toInstant(), partition, Inspection.UNINSPECTED);
    }
    static List<EvaluationRow> fixtureRows(Manifest m) { return List.of(fixtureRow(m, 0, Partition.TRAIN), fixtureRow(m, 5, Partition.VALIDATION), fixtureRow(m, 10, Partition.TEST)); }
    private static void issue(GuardResult result, String code) { if (result.issues().stream().noneMatch(i -> i.code().equals(code))) throw new AssertionError("Missing " + code); }

    public static Map<String, Object> smoke() {
        long start = System.nanoTime(); var checks = new ArrayList<Check>();
        Contract contract = fixtureContract(); var pairs = fixturePairs(); Metrics measured = metrics(contract, pairs);
        check(checks, "hand_calculated_metrics", pairs, () -> {
            equal(measured.rowWeighted().mae(), 2); equal(measured.rowWeighted().rmse(), Math.sqrt(14.0 / 3));
            equal(measured.rowWeighted().signedBias(), 2.0 / 3); equal(measured.rowWeighted().directionAgreementPercent(), 100.0 / 3);
            equal(measured.equalDateWeighted().mae(), 2.25); equal(measured.equalDateWeighted().rmse(), Math.sqrt(5.75));
            equal(measured.equalDateWeighted().signedBias(), 1.25); equal(measured.equalDateWeighted().directionAgreementPercent(), 25);
        });
        check(checks, "order_independence", pairs, () -> { var reverse = new ArrayList<>(pairs); Collections.reverse(reverse); require(measured.equals(metrics(contract, reverse)), "Order changed metrics"); });
        check(checks, "empty_unavailable", List.of(), () -> { var r = metrics(contract, List.of()); require(r.rowWeighted() == null && r.equalDateWeighted() == null && !r.trainingAuthorized(), "Empty reported success"); });
        check(checks, "duplicate_rejected", List.of(pairs.get(0), pairs.get(0)), () -> rejects(() -> metrics(contract, List.of(pairs.get(0), pairs.get(0)))));
        for (double invalid : new double[]{Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Double.MAX_VALUE}) {
            check(checks, "invalid_number_" + invalid, Double.toString(invalid), () -> rejects(() -> metrics(contract, List.of(new Pair("A", pairs.get(0).decisionDate(), "X", invalid, 0, contract)))));
        }
        check(checks, "mixed_contract_rejected", "HORIZON_2_VS_3", () -> rejects(() -> metrics(contract, List.of(new Pair("A", pairs.get(0).decisionDate(), "X", 0, 0, new Contract(3, "PERCENTAGE_POINTS", "SYNTHETIC_ONLY"))))));
        check(checks, "flat_sign_including_negative_zero", "0_VS_NEGATIVE_ZERO", () -> equal(metrics(contract, List.of(new Pair("A", pairs.get(0).decisionDate(), "X", 0, -0.0, contract))).rowWeighted().directionAgreementPercent(), 100));
        Manifest manifest = fixtureManifest(); var rows = fixtureRows(manifest); GuardResult guarded = guard(manifest, rows);
        check(checks, "valid_declared_metadata", List.of(manifest, rows), () -> require(guarded.issues().isEmpty() && !guarded.trainingAuthorized(), "Valid fixture failed"));
        for (Partition partition : List.of(Partition.TRAIN, Partition.VALIDATION)) {
            int at = partition == Partition.TRAIN ? 0 : 1;
            var leaking = new ArrayList<>(rows); EvaluationRow r = rows.get(at);
            Partition next = partition == Partition.TRAIN ? Partition.VALIDATION : Partition.TEST;
            leaking.set(at, new EvaluationRow(r.inference(), manifest.windows().get(next).first().atStartOfDay(INDIA).toInstant(), partition, r.inspection()));
            check(checks, "overlap_" + partition, List.of(manifest, leaking), () -> issue(guard(manifest, leaking), "LABEL_OVERLAP_NEXT_PARTITION"));
        }
        var splitDate = new ArrayList<>(rows); var first = rows.get(0);
        splitDate.add(new EvaluationRow(new InferenceInput("B", first.inference().decisionAt(), first.inference().featuresAvailableAt(), Map.of("return5", 1.0)), first.labelEndAt(), Partition.VALIDATION, Inspection.UNINSPECTED));
        check(checks, "same_date_split_rejected", splitDate, () -> issue(guard(manifest, splitDate), "DATE_CROSSES_PARTITIONS"));
        Manifest inspected = new Manifest(manifest.sessions(), manifest.windows(), 2, 1, manifest.availabilityPolicy(), List.of(manifest.windows().get(Partition.TEST)));
        check(checks, "inspected_period_rejected", List.of(inspected, rows), () -> issue(guard(inspected, rows), "TEST_NOT_UNTOUCHED"));
        check(checks, "unknown_availability_rejected", "NULL_AVAILABLE_AT", () -> rejects(() -> new InferenceInput("A", first.inference().decisionAt(), null, Map.of("return5", 1.0))));
        check(checks, "future_availability_rejected", "AFTER_DECISION", () -> rejects(() -> new InferenceInput("A", first.inference().decisionAt(), first.inference().decisionAt().plusSeconds(1), Map.of("return5", 1.0))));
        check(checks, "outcome_feature_rejected", "actualRank", () -> rejects(() -> new InferenceInput("A", first.inference().decisionAt(), first.inference().decisionAt(), Map.of("actualRank", 1.0))));
        Manifest gap = new Manifest(manifest.sessions(), manifest.windows(), 2, 4, manifest.availabilityPolicy(), List.of());
        check(checks, "insufficient_gap_rejected", gap, () -> rejects(() -> guard(gap, rows)));
        var duplicateRows = new ArrayList<>(rows); duplicateRows.add(first);
        check(checks, "duplicate_evaluation_rejected", duplicateRows, () -> issue(guard(manifest, duplicateRows), "DUPLICATE_ROW"));
        check(checks, "empty_partitions_rejected", List.of(), () -> issue(guard(manifest, List.of()), "EMPTY_TRAIN"));
        check(checks, "guard_order_independence", rows, () -> { var reverse = new ArrayList<>(rows); Collections.reverse(reverse); require(guarded.equals(guard(manifest, reverse)), "Order changed guard"); });
        var result = new LinkedHashMap<String, Object>();
        result.put("version", VERSION); result.put("status", checks.stream().allMatch(Check::passed) ? "SYNTHETIC_CHECKS_PASSED" : "SYNTHETIC_CHECKS_FAILED");
        result.put("syntheticOnly", true); result.put("trainingAuthorized", false); result.put("databaseWritesPerformed", false);
        result.put("providerCallCount", 0); result.put("modelCallCount", 0); result.put("ordersCreated", 0);
        result.put("javaVersion", System.getProperty("java.version")); result.put("fixtureContract", contract);
        result.put("metricFixtureRows", pairs); result.put("guardFixtureManifest", manifest); result.put("guardFixtureRows", rows);
        result.put("metrics", measured); result.put("guard", guarded); result.put("checks", checks);
        result.put("checkCount", checks.size()); result.put("failedCheckCount", checks.stream().filter(c -> !c.passed()).count());
        result.put("elapsedMillis", (System.nanoTime() - start) / 1_000_000.0);
        result.put("limitations", List.of("Synthetic calculator/metadata checks only; not forecasting accuracy", "No source-policy certification, fitting or untouched real-data evaluation", "No calibrated probabilities, ranking, portfolio returns or costs"));
        return result;
    }
    /** No external data entry point: this lab is reached only by the fixed synthetic CLI. */
    public static final class Baselines {
        public static final String VERSION = "SYNTHETIC_NUMERICAL_BASELINES_V1";
        public static final double RIDGE = 0.01;
        public static final Contract CONTRACT = new Contract(20, "PERCENTAGE_POINTS", "SYNTHETIC_ONLY");
        public record Labeled(EvaluationRow metadata, double target) { }
        public record Model(String version, List<String> features, List<Double> means, List<Double> scales,
                            List<Double> weights, double intercept, double penalty, int trainingRows,
                            Instant fitCutoff, String trainingSha256) {
            public Model {
                require("SYNTHETIC_RIDGE_V1".equals(version) && List.of("return5", "volumeRatio20").equals(features), "Unknown model contract");
                require(means != null && scales != null && weights != null && means.size() == 2 && scales.size() == 2 && weights.size() == 2, "Invalid parameter dimensions");
                for (int i=0;i<2;i++) { finite(means.get(i)); finite(scales.get(i)); finite(weights.get(i)); require(scales.get(i)>0,"Invalid scale"); }
                finite(intercept); require(penalty == RIDGE && trainingRows > 0 && trainingRows <= MAX_ROWS && fitCutoff != null, "Invalid fit metadata");
                require(trainingSha256 != null && trainingSha256.matches("[a-f0-9]{64}"), "Missing training fingerprint");
                features=List.copyOf(features); means=List.copyOf(means); scales=List.copyOf(scales); weights=List.copyOf(weights);
            }
        }
        public record Ranking(int dateCount, int correlationDateCount, int unavailableCorrelationDates,
                              Double meanSpearman, double tieInclusiveTopMeanPercent, int selectedRowCount) { }
        public record Comparison(String predictor, Metrics errors, Ranking ranking, List<Pair> predictions) { }
        public record PartitionComparison(List<Comparison> comparisons, List<String> lowestMaePredictors) { }
        public record Scenario(String name, String fixtureSha256, GuardResult guard, Model model, String modelSha256,
                               PartitionComparison validation, PartitionComparison test, double elapsedMillis) { }

        static List<Labeled> orderedTraining(List<Labeled> input, Instant cutoff) {
            require(input != null && !input.isEmpty() && input.size() <= MAX_ROWS && cutoff != null, "Training rows/cutoff required");
            var keys=new HashSet<String>(); var ordered=new ArrayList<Labeled>();
            for (Labeled row : input) {
                require(row != null && row.metadata() != null && row.metadata().inference() != null, "Missing training row");
                var m=row.metadata(); var x=m.inference();
                require(m.partition() == Partition.TRAIN && m.labelEndAt() != null && m.labelEndAt().isAfter(x.decisionAt())
                        && m.labelEndAt().isBefore(cutoff), "Only matured TRAIN labels before cutoff may fit");
                finite(row.target()); require(x.features().containsKey("return5"), "Critical feature return5 missing");
                require(Set.of("return5","volumeRatio20").containsAll(x.features().keySet()), "Unexpected learner feature");
                String key=x.instrument()+":"+x.decisionAt().atZone(INDIA).toLocalDate();
                require(keys.add(key),"Duplicate training row"); ordered.add(row);
            }
            ordered.sort(Comparator.comparing((Labeled r)->r.metadata().inference().decisionAt()).thenComparing(r->r.metadata().inference().instrument()));
            return List.copyOf(ordered);
        }
        static double meanTarget(List<Labeled> train) { double sum=0;for(var r:train)sum=finite(sum+r.target());return sum/train.size(); }
        public static Model fit(List<Labeled> input, Instant cutoff) {
            var train=orderedTraining(input,cutoff); var names=List.of("return5","volumeRatio20");
            double[] means=new double[2], scales=new double[2];
            for(int j=0;j<2;j++) {
                int count=0;
                for(var r:train){Double v=r.metadata().inference().features().get(names.get(j)); if(v!=null){means[j]=finite(means[j]+v);count++;}}
                require(count>0,"All training values missing for "+names.get(j)); means[j]/=count;
                double sum=0;
                for(var r:train){double delta=finite(r.metadata().inference().features().getOrDefault(names.get(j),means[j])-means[j]);sum=finite(sum+finite(delta*delta));}
                scales[j]=Math.sqrt(sum/train.size()); if(scales[j]==0)scales[j]=1;
            }
            double yMean=meanTarget(train), a=RIDGE,b=0,d=RIDGE,u=0,v=0;
            for(var row:train){
                var f=row.metadata().inference().features();
                double x=finite((f.get("return5")-means[0])/scales[0]);
                double z=finite((f.getOrDefault("volumeRatio20",means[1])-means[1])/scales[1]);
                double y=finite(row.target()-yMean), n=train.size();
                a=finite(a+finite(x*x)/n);b=finite(b+finite(x*z)/n);d=finite(d+finite(z*z)/n);
                u=finite(u+finite(x*y)/n);v=finite(v+finite(z*y)/n);
            }
            double determinant=finite(a*d-b*b); require(determinant>0,"Unstable ridge system");
            double w0=finite((d*u-b*v)/determinant),w1=finite((a*v-b*u)/determinant);
            return new Model("SYNTHETIC_RIDGE_V1",names,List.of(means[0],means[1]),List.of(scales[0],scales[1]),
                    List.of(w0,w1),yMean,RIDGE,train.size(),cutoff,sha256(json(train)));
        }
        public static double predict(Model model, InferenceInput input) {
            require(model!=null && input!=null && input.features().containsKey("return5"),"Missing predictor/critical feature");
            require(Set.of("return5","volumeRatio20").containsAll(input.features().keySet()),"Unexpected learner feature");
            double prediction=model.intercept();
            for(int j=0;j<2;j++) {
                double value=input.features().getOrDefault(model.features().get(j),model.means().get(j));
                prediction=finite(prediction+finite(model.weights().get(j)*finite((value-model.means().get(j))/model.scales().get(j))));
            }
            return prediction;
        }
        private static double[] ranks(double[] values) {
            Integer[] order=new Integer[values.length];for(int i=0;i<order.length;i++)order[i]=i;
            Arrays.sort(order,Comparator.comparingDouble(i->values[i])); double[] ranks=new double[values.length];
            for(int i=0;i<order.length;){int end=i+1;while(end<order.length && values[order[end]]==values[order[i]])end++;
                double rank=(i+1+end)/2.0;for(int k=i;k<end;k++)ranks[order[k]]=rank;i=end;}
            return ranks;
        }
        public static Ranking ranking(List<Pair> rows) {
            metrics(CONTRACT,rows);require(!rows.isEmpty(),"No ranking observations");
            var dates=new TreeMap<LocalDate,List<Pair>>();
            for(var row:rows)dates.computeIfAbsent(row.decisionDate(),ignored->new ArrayList<>()).add(row);
            double correlationSum=0,topSum=0;int available=0,selected=0;
            for(var group:dates.values()){
                group.sort(Comparator.comparing(Pair::instrument));
                double[] p=ranks(group.stream().mapToDouble(Pair::predicted).toArray());
                double[] y=ranks(group.stream().mapToDouble(Pair::observed).toArray());
                double center=(group.size()+1)/2.0,cov=0,vp=0,vy=0;
                for(int i=0;i<group.size();i++){double x=p[i]-center,z=y[i]-center;cov+=x*z;vp+=x*x;vy+=z*z;}
                if(vp>0 && vy>0){correlationSum+=cov/Math.sqrt(vp*vy);available++;}
                double top=group.stream().mapToDouble(Pair::predicted).max().orElseThrow(),sum=0;int count=0;
                for(var row:group)if(row.predicted()==top){sum=finite(sum+row.observed());count++;}
                topSum=finite(topSum+sum/count);selected+=count;
            }
            return new Ranking(dates.size(),available,dates.size()-available,available==0?null:correlationSum/available,topSum/dates.size(),selected);
        }
        static Manifest manifest() {
            List<LocalDate> dates=new ArrayList<>();for(int i=0;i<150;i++)dates.add(LocalDate.of(2020,1,1).plusDays(2L*i));
            return new Manifest(List.copyOf(dates),Map.of(Partition.TRAIN,new Window(dates.get(0),dates.get(39)),
                    Partition.VALIDATION,new Window(dates.get(65),dates.get(79)),Partition.TEST,new Window(dates.get(105),dates.get(119))),
                    20,5,"SYNTHETIC_KNOWN_AVAILABILITY",List.of());
        }
        static List<Labeled> data(String scenario) {
            require(Set.of("LINEAR_SIGNAL","CONSTANT_TARGET","REGIME_REVERSAL").contains(scenario),"Unknown synthetic scenario");
            var m=manifest();var rows=new ArrayList<Labeled>();
            for(var partition:Partition.values())for(int i=0;i<m.sessions().size();i++)if(inside(m.sessions().get(i),m.windows().get(partition))) {
                for(int stock=0;stock<3;stock++){
                    double x=i%9-4+stock*0.15,z=1+((i+stock)%5)*0.25;
                    var features=new LinkedHashMap<String,Double>();features.put("return5",x);
                    if(!(i%7==0 && stock==1))features.put("volumeRatio20",z);
                    var base=fixtureRow(m,i,partition);
                    var input=new InferenceInput("SYNTH_"+stock,base.inference().decisionAt(),base.inference().featuresAvailableAt(),features);
                    double y=switch(scenario){case "LINEAR_SIGNAL"->1.25+1.8*x-1.2*(z-1);case "CONSTANT_TARGET"->2;default->(partition==Partition.TRAIN?2:-2)*x;};
                    rows.add(new Labeled(new EvaluationRow(input,base.labelEndAt(),partition,Inspection.UNINSPECTED),y));
                }
            }
            return List.copyOf(rows);
        }
        static PartitionComparison compare(Model model, double trainMean, List<Labeled> heldOut) {
            var comparisons=new ArrayList<Comparison>();
            for(String id:List.of("ZERO","TRAIN_MEAN","RIDGE")){
                List<Pair> pairs=heldOut.stream().map(row->{var x=row.metadata().inference();double predicted=switch(id){case "ZERO"->0;case "TRAIN_MEAN"->trainMean;default->predict(model,x);};
                    return new Pair(x.instrument(),x.decisionAt().atZone(INDIA).toLocalDate(),id,predicted,row.target(),CONTRACT);}).toList();
                comparisons.add(new Comparison(id,metrics(CONTRACT,pairs),ranking(pairs),pairs));
            }
            double best=comparisons.stream().mapToDouble(c->c.errors().equalDateWeighted().mae()).min().orElseThrow();
            return new PartitionComparison(List.copyOf(comparisons),comparisons.stream().filter(c->Math.abs(c.errors().equalDateWeighted().mae()-best)<=1e-9).map(Comparison::predictor).toList());
        }
        static Scenario scenario(String name) {
            long start=System.nanoTime();var data=data(name);var m=manifest();
            var checked=guard(m,data.stream().map(Labeled::metadata).toList());require(checked.issues().isEmpty(),"Synthetic fixture leakage");
            var train=data.stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList();
            var model=fit(train,m.windows().get(Partition.VALIDATION).first().atStartOfDay(INDIA).toInstant());
            return new Scenario(name,sha256(json(data)),checked,model,sha256(json(model)),
                    compare(model,meanTarget(train),data.stream().filter(r->r.metadata().partition()==Partition.VALIDATION).toList()),
                    compare(model,meanTarget(train),data.stream().filter(r->r.metadata().partition()==Partition.TEST).toList()),(System.nanoTime()-start)/1_000_000.0);
        }
        static double error(PartitionComparison c,String id){return c.comparisons().stream().filter(r->r.predictor().equals(id)).findFirst().orElseThrow().errors().equalDateWeighted().mae();}
        static Map<String,Object> smokeBundle() {
            long started=System.nanoTime();var regression=smoke();var checks=new ArrayList<Check>();var scenarios=new ArrayList<Scenario>();
            for(String name:List.of("LINEAR_SIGNAL","CONSTANT_TARGET","REGIME_REVERSAL"))scenarios.add(scenario(name));
            Scenario linear=scenarios.get(0),constant=scenarios.get(1),reversal=scenarios.get(2);
            check(checks,"linear_signal_beats_references",linear.fixtureSha256(),()->{
                for(var c:List.of(linear.validation(),linear.test()))require(error(c,"RIDGE")<error(c,"ZERO") && error(c,"RIDGE")<error(c,"TRAIN_MEAN"),"Linear fixture not learned");});
            check(checks,"constant_target_retains_tie",constant.fixtureSha256(),()->{
                for(var c:List.of(constant.validation(),constant.test())){equal(error(c,"RIDGE"),0);equal(error(c,"TRAIN_MEAN"),0);require(c.lowestMaePredictors().equals(List.of("TRAIN_MEAN","RIDGE")),"Tie lost");}});
            check(checks,"reversal_exposes_underperformance",reversal.fixtureSha256(),()->{
                for(var c:List.of(reversal.validation(),reversal.test()))require(error(c,"RIDGE")>error(c,"ZERO"),"Underperformance hidden");});
            var train=data("LINEAR_SIGNAL").stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList();var model=linear.model();
            check(checks,"shuffle_training_same_artifact",train,()->{var reversed=new ArrayList<>(train);Collections.reverse(reversed);require(model.equals(fit(reversed,model.fitCutoff())),"Fit depends on order");});
            check(checks,"heldout_targets_cannot_change_fit_or_predictions",linear.fixtureSha256(),()->{
                var changed=data("LINEAR_SIGNAL").stream().map(r->r.metadata().partition()==Partition.TRAIN?r:new Labeled(r.metadata(),r.target()+9999)).toList();
                var refit=fit(changed.stream().filter(r->r.metadata().partition()==Partition.TRAIN).toList(),model.fitCutoff());require(model.equals(refit),"Heldout target leakage");
                for(var r:changed)equal(predict(model,r.metadata().inference()),predict(refit,r.metadata().inference()));});
            var held=data("LINEAR_SIGNAL").stream().filter(r->r.metadata().partition()==Partition.TEST).findFirst().orElseThrow();
            check(checks,"heldout_rows_rejected_by_fit",held,()->rejects(()->fit(List.of(held),model.fitCutoff())));
            check(checks,"unmatured_target_rejected",train.get(0),()->rejects(()->fit(train,train.get(0).metadata().labelEndAt())));
            check(checks,"duplicate_training_rejected",train.get(0),()->rejects(()->fit(List.of(train.get(0),train.get(0)),model.fitCutoff())));
            var x=held.metadata().inference();
            check(checks,"optional_missing_uses_training_mean",model,()->{
                var missing=new InferenceInput(x.instrument(),x.decisionAt(),x.featuresAvailableAt(),Map.of("return5",x.features().get("return5")));
                var filled=new InferenceInput(x.instrument(),x.decisionAt(),x.featuresAvailableAt(),Map.of("return5",x.features().get("return5"),"volumeRatio20",model.means().get(1)));
                equal(predict(model,missing),predict(model,filled));});
            check(checks,"critical_missing_rejected",x,()->rejects(()->predict(model,new InferenceInput(x.instrument(),x.decisionAt(),x.featuresAvailableAt(),Map.of("volumeRatio20",1.0)))));
            var date=LocalDate.of(2020,1,1);var ties=List.of(new Pair("A",date,"TIES",2,1,CONTRACT),new Pair("B",date,"TIES",2,3,CONTRACT),new Pair("C",date,"TIES",1,0,CONTRACT));
            check(checks,"ranking_average_ties_and_top_ties",ties,()->{var r=ranking(ties);equal(r.meanSpearman(),Math.sqrt(3)/2);equal(r.tieInclusiveTopMeanPercent(),2);require(r.selectedRowCount()==2,"Top ties broken arbitrarily");});
            var flat=List.of(new Pair("A",date,"FLAT",0,1,CONTRACT),new Pair("B",date,"FLAT",0,2,CONTRACT));
            check(checks,"constant_ranking_unavailable",flat,()->{var r=ranking(flat);require(r.meanSpearman()==null && r.unavailableCorrelationDates()==1,"Undefined correlation fabricated");});
            check(checks,"parameter_artifact_copy_prediction_parity",model,()->{var copy=new Model(model.version(),model.features(),model.means(),model.scales(),model.weights(),model.intercept(),model.penalty(),model.trainingRows(),model.fitCutoff(),model.trainingSha256());equal(predict(copy,x),predict(model,x));});
            var result=new LinkedHashMap<String,Object>();
            result.put("version",VERSION);result.put("evaluationRegression",regression);result.put("checks",checks);result.put("checkCount",checks.size());
            long failed=checks.stream().filter(c->!c.passed()).count();result.put("failedCheckCount",failed);
            result.put("status",failed==0 && "SYNTHETIC_CHECKS_PASSED".equals(regression.get("status"))?"SYNTHETIC_CHECKS_PASSED":"SYNTHETIC_CHECKS_FAILED");
            result.put("scenarios",scenarios);result.put("manifest",manifest());result.put("configuration",Map.of("ridgePenalty",RIDGE,"primaryMetric","EQUAL_DATE_MAE","tieTolerance",1e-9,"horizonSessions",20,"scenarioCount",3));
            result.put("syntheticOnly",true);result.put("syntheticTrainingPerformed",true);result.put("trainingAuthorized",false);result.put("realMarketTrainingAuthorized",false);
            result.put("databaseWritesPerformed",false);result.put("providerCallCount",0);result.put("modelCallCount",0);result.put("ordersCreated",0);result.put("automaticPromotionEnabled",false);
            result.put("elapsedMillis",(System.nanoTime()-started)/1_000_000.0);result.put("javaVersion",System.getProperty("java.version"));
            result.put("limitations",List.of("Fixed synthetic scenarios; no measured stock prediction accuracy","No real data, tuning, cost/portfolio simulation or probability calibration","Parameter artifact for synthetic tests only; no production model promotion"));
            return result;
        }
    }

    static String sha256(String text) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8))); }
        catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    /** Small dependency-free encoder; sorted map keys make fixture hashes reproducible. */
    public static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Number number) { finite(number.doubleValue()); return number.toString(); }
        if (value instanceof Boolean) return value.toString();
        if (value instanceof Map<?, ?> map) {
            var sorted = new TreeMap<String, Object>(); map.forEach((k,v) -> sorted.put(k.toString(), v));
            var entries = new ArrayList<String>(); sorted.forEach((k,v) -> entries.add(json(k) + ":" + json(v)));
            return "{" + String.join(",", entries) + "}";
        }
        if (value instanceof Collection<?> list) return "[" + String.join(",", list.stream().map(NumericalEvaluationEngineering::json).toList()) + "]";
        if (value.getClass().isRecord()) {
            var fields = new LinkedHashMap<String, Object>();
            try { for (RecordComponent c : value.getClass().getRecordComponents()) fields.put(c.getName(), c.getAccessor().invoke(value)); }
            catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
            return json(fields);
        }
        String text = value.toString(); var out = new StringBuilder("\"");
        for (int i = 0; i < text.length(); i++) { char c = text.charAt(i);
            if (c == '"' || c == '\\') out.append('\\').append(c);
            else if (c < 32) out.append(String.format(Locale.ROOT, "\\u%04x", (int)c)); else out.append(c);
        }
        return out.append('"').toString();
    }
    public static void main(String[] args) {
        if (args.length != 1 || !Set.of("--synthetic-smoke","--synthetic-baselines").contains(args[0])) throw new IllegalArgumentException("Only fixed synthetic suites are supported; no market-data input");
        Map<String, Object> result = "--synthetic-baselines".equals(args[0]) ? Baselines.smokeBundle() : smoke(); System.out.println(json(result));
        if (!"SYNTHETIC_CHECKS_PASSED".equals(result.get("status"))) System.exit(2);
    }
}
