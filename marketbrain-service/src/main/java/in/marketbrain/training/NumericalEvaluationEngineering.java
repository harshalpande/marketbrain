package in.marketbrain.training;

import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** Standalone, JDK-only evaluation engineering. No Spring bean, I/O data source or fitter.
 * main runs fixed synthetic fixtures only; pure methods also serve unit tests.
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
        if (args.length != 1 || !"--synthetic-smoke".equals(args[0])) throw new IllegalArgumentException("Only --synthetic-smoke is supported; no market-data input");
        Map<String, Object> result = smoke(); System.out.println(json(result));
        if (!"SYNTHETIC_CHECKS_PASSED".equals(result.get("status"))) System.exit(2);
    }
}
