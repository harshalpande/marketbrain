package in.marketbrain.training;

import in.marketbrain.feature.FeatureValues;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;

/** Research preparation only. Rebuilds features from bounded saved bars; no fitting or certification. */
public final class NumericalResearchMapping {
    public static final String VERSION = "NUMERICAL_RESEARCH_MAPPING_V1";
    public static final List<String> GATES = List.of("PRICE_ACTION_PROVENANCE_UNVERIFIED",
            "HISTORICAL_AVAILABILITY_UNVERIFIED", "SOURCE_RIGHTS_SCOPE_REVIEW_PENDING",
            "EVALUATION_POLICY_AND_FIT_APPROVAL_PENDING");

    // The only numerical input DTO. Identity, outcomes and eligibility metadata are NOT features.
    public record Vector(BigDecimal dailyReturnPercent, BigDecimal closeToSma20Percent,
            BigDecimal closeToSma50Percent, BigDecimal closeToSma200Percent,
            BigDecimal ema12ToEma26Percent, BigDecimal rsi14, BigDecimal atr14ToClosePercent,
            BigDecimal annualizedVolatility20Percent, BigDecimal volumeRatio20,
            BigDecimal rangePosition252Percent) { }
    public record Row(long instrumentId, String symbol, LocalDate decisionDate, Instant proposedCutoff,
            String featureStatus, Vector features, List<Long> sourceCandleIds,
            int receivedAfterCutoffCount, int missingReceivedAtCount,
            boolean mappingReady, boolean trainingEligible, List<String> blockers) { }
    public record DateCoverage(LocalDate decisionDate, int rowCount, int mappingReadyCount,
            int trainingEligibleCount) { }
    public record Result(String version, String status, UUID datasetRunId, String datasetManifestHash,
            String calendarSessionSha256, List<String> featureNames, int rowCount, int mappingReadyCount,
            int trainingEligibleCount, List<DateCoverage> dateCoverage, Map<String,Integer> blockerCounts,
            List<Row> rows, int certifiedLabelCount, boolean trainingAuthorized,
            boolean databaseWritesPerformed, int databaseQueryCount, int providerCallCount,
            int modelCallCount, int ordersCreated, String limitations) { }

    public Result build(NumericalResearchExport.Input input) {
        // Reuse bounds, calendar, source, exclusion and warm-up checks; never trust saved outcome fields.
        var export = new NumericalResearchExport().buildExpanded(input);
        var closes = new HashMap<Long,Map<LocalDate,BigDecimal>>();
        for (var instrument : input.instruments()) {
            var byDate = new HashMap<LocalDate,BigDecimal>();
            instrument.bars().forEach(b -> byDate.put(b.date(), b.close()));
            closes.put(instrument.instrumentId(), byDate);
        }
        var rows = new ArrayList<Row>();
        var counts = new TreeMap<String,Integer>();
        var coverage = new TreeMap<LocalDate,int[]>();
        for (var original : export.rows()) {
            var snapshot = original.featureSnapshot();
            var blockers = new ArrayList<>(GATES);
            Vector vector = null;
            if (!"MATCHES_REVIEWED_CALENDAR".equals(original.featureStatus())) {
                blockers.add("FEATURE_WINDOW_INVALID");
            } else {
                try { vector = map(snapshot.features(), closes.get(original.instrumentId()).get(original.decisionDate())); }
                catch (IllegalArgumentException e) { blockers.add("FEATURE_MAPPING_INVALID"); }
            }
            if (snapshot.receivedAfterCutoffCount() > 0) blockers.add("STORED_RECEIPT_AFTER_CUTOFF");
            if (snapshot.missingReceivedAtCount() > 0) blockers.add("STORED_RECEIPT_MISSING");
            // Even earlier receipts do not prove original publication or immutable vintages.
            for (var blocker : blockers) counts.merge(blocker, 1, Integer::sum);
            var bucket = coverage.computeIfAbsent(original.decisionDate(), d -> new int[2]);
            bucket[0]++; if (vector != null) bucket[1]++;
            rows.add(new Row(original.instrumentId(), original.symbol(), original.decisionDate(),
                    original.decisionDate().atTime(16,0).atZone(ZoneId.of("Asia/Kolkata")).toInstant(),
                    original.featureStatus(), vector, List.copyOf(snapshot.sourceCandleIds()),
                    snapshot.receivedAfterCutoffCount(), snapshot.missingReceivedAtCount(),
                    vector != null, false, List.copyOf(blockers)));
        }
        var dates = coverage.entrySet().stream().map(e -> new DateCoverage(e.getKey(),e.getValue()[0],e.getValue()[1],0)).toList();
        return new Result(VERSION,"MAPPED_RESEARCH_TRAINING_BLOCKED",input.datasetRunId(),input.datasetManifestHash(),
                export.calendarSessionSha256(),NumericalDataContract.draft().candidateFeatures(),rows.size(),
                (int)rows.stream().filter(Row::mappingReady).count(),0,dates,Collections.unmodifiableMap(counts),
                List.copyOf(rows),0,false,false,0,0,0,0,
                "Restricted retrospective development cohort; mapping readiness is not training eligibility. "
                +"Receipt timestamps are diagnostics, not publication evidence. No label certification, folds, fit or trading. "
                +"Caller-supplied saved bars are not reauthenticated. Future outcomes excluded from feature DTO. "
                +"Ten-feature research mapping is not the two-feature synthetic ridge learner.");
    }

    static Vector map(FeatureValues f, BigDecimal close) {
        if (f == null || close == null || close.signum() <= 0) throw new IllegalArgumentException("Missing features/close");
        var values = Arrays.asList(f.dailyReturnPercent(), f.sma20(), f.sma50(), f.sma200(), f.ema12(),
                f.ema26(), f.rsi14(), f.atr14(), f.annualizedVolatility20Percent(), f.volumeRatio20(), f.rangePosition252Percent());
        if (values.contains(null) || f.ema12().signum() <= 0 || f.atr14().signum() < 0
                || f.annualizedVolatility20Percent().signum() < 0 || f.volumeRatio20().signum() < 0
                || !bounded(f.rsi14()) || !bounded(f.rangePosition252Percent())) throw new IllegalArgumentException("Invalid feature values");
        return new Vector(f.dailyReturnPercent(), deviation(close,f.sma20()), deviation(close,f.sma50()),
                deviation(close,f.sma200()), deviation(f.ema12(),f.ema26()), f.rsi14(),
                percent(f.atr14(),close),f.annualizedVolatility20Percent(),f.volumeRatio20(),f.rangePosition252Percent());
    }
    private static boolean bounded(BigDecimal x) { return x.signum() >= 0 && x.compareTo(BigDecimal.valueOf(100)) <= 0; }
    private static BigDecimal deviation(BigDecimal numerator, BigDecimal denominator) { return percent(numerator.subtract(denominator),denominator); }
    private static BigDecimal percent(BigDecimal numerator, BigDecimal denominator) {
        if (denominator.signum() <= 0) throw new IllegalArgumentException("Nonpositive denominator");
        return numerator.multiply(BigDecimal.valueOf(100)).divide(denominator,8,RoundingMode.HALF_UP);
    }
}
