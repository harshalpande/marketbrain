package in.marketbrain.training;

import in.marketbrain.feature.FeatureCandle;
import in.marketbrain.feature.FeaturePreview;
import in.marketbrain.feature.FeaturePreviewService;
import in.marketbrain.feature.FeatureUniversePreview;
import in.marketbrain.feature.FeatureUniversePreviewService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class SwingTrainingDatasetPreviewService {

    public static final String DATASET_CONTRACT_VERSION = "SWING_TRAINING_V1";
    static final List<Integer> HORIZONS = List.of(5, 20, 60);
    static final String BENCHMARK_DEFINITION = "CURRENT_SNAPSHOT_EQUAL_WEIGHT_PROXY";
    static final String HISTORICAL_MEMBERSHIP_STATUS = "CURRENT_SNAPSHOT_ONLY";
    private static final Logger LOGGER = LoggerFactory.getLogger(SwingTrainingDatasetPreviewService.class);
    private static final int MAXIMUM_COST_BPS = 1_000;

    private static final String FUTURE_CANDLES_SQL = """
            WITH members AS (
                SELECT member.instrument_id, member.source_symbol
                FROM universe_snapshot_member member
                WHERE member.snapshot_id = ?
                  AND member.match_status = 'MATCHED'
            ), ranked AS (
                SELECT member.source_symbol,
                       member.instrument_id,
                       (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                       source.code AS source_code,
                       candle.open_price,
                       candle.high_price,
                       candle.low_price,
                       candle.close_price,
                       candle.volume,
                       EXISTS (
                           SELECT 1
                           FROM market_data_feature_exclusion exclusion
                           WHERE exclusion.instrument_id = candle.instrument_id
                             AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                                 BETWEEN exclusion.exclusion_from AND exclusion.exclusion_to
                       ) AS excluded,
                       ROW_NUMBER() OVER (
                           PARTITION BY candle.instrument_id,
                                        (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                           ORDER BY CASE source.code
                               WHEN 'NSE_BHAVCOPY' THEN 1
                               WHEN 'UPSTOX' THEN 2
                               ELSE 3
                           END,
                           candle.received_at DESC,
                           candle.id DESC
                       ) AS source_rank
                FROM members member
                JOIN market_candle candle ON candle.instrument_id = member.instrument_id
                JOIN market_data_source source ON source.id = candle.source_id
                WHERE candle.interval_code = 'days:1'
                  AND candle.is_complete = TRUE
                  AND source.code IN ('UPSTOX', 'NSE_BHAVCOPY')
                  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date > ?
                  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date <= ?
            )
            SELECT source_symbol, instrument_id, trading_date, source_code, open_price, high_price,
                   low_price, close_price, volume, excluded
            FROM ranked
            WHERE source_rank = 1
            ORDER BY trading_date, instrument_id
            """;

    private final JdbcTemplate jdbcTemplate;
    private final FeatureUniversePreviewService featurePreviewService;
    private final SwingOutcomeLabelCalculator labelCalculator;
    private final SwingTrainingDatasetManifestHasher manifestHasher;

    public SwingTrainingDatasetPreviewService(
            JdbcTemplate jdbcTemplate,
            FeatureUniversePreviewService featurePreviewService,
            SwingOutcomeLabelCalculator labelCalculator,
            SwingTrainingDatasetManifestHasher manifestHasher
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.featurePreviewService = featurePreviewService;
        this.labelCalculator = labelCalculator;
        this.manifestHasher = manifestHasher;
    }

    @Transactional(readOnly = true, timeout = 1_800)
    public SwingTrainingDatasetPreview preview(
            LocalDate asOf,
            LocalDate labelThrough,
            int assumedRoundTripCostBps
    ) {
        validateRequest(asOf, labelThrough, assumedRoundTripCostBps);
        long startedAt = System.nanoTime();
        FeatureUniversePreview features = featurePreviewService.preview(asOf);
        validateFeaturePreview(features, asOf);
        FutureCandleSet future = loadFutureCandles(features, asOf, labelThrough);
        Map<Integer, LocalDate> outcomeDates = outcomeDates(future.marketSessions());
        Set<LocalDate> marketSessions = new HashSet<>(future.marketSessions());

        List<SwingTrainingCohortItem> initialItems = new ArrayList<>();
        for (FeaturePreview feature : features.instruments()) {
            if (!"ELIGIBLE".equals(feature.status())) {
                initialItems.add(new SwingTrainingCohortItem(
                        feature.symbol(), feature.status(), feature, List.of(), HORIZONS,
                        "The point-in-time feature input is not eligible for outcome labeling."));
                continue;
            }
            List<FeatureCandle> eligibleFuture = future.candlesBySymbol()
                    .getOrDefault(feature.symbol(), List.of()).stream()
                    .filter(candle -> !candle.excluded())
                    .filter(candle -> marketSessions.contains(candle.tradingDate()))
                    .toList();
            List<SwingOutcomeLabel> labels = labelCalculator.calculate(
                    feature.latestCandle().close(), eligibleFuture,
                    outcomeDates, assumedRoundTripCostBps);
            Set<Integer> presentHorizons = labels.stream()
                    .map(SwingOutcomeLabel::horizonSessions)
                    .collect(java.util.stream.Collectors.toSet());
            List<Integer> missing = HORIZONS.stream()
                    .filter(horizon -> !presentHorizons.contains(horizon))
                    .toList();
            String status = missing.isEmpty() ? "LABELED" : "RIGHT_CENSORED";
            initialItems.add(new SwingTrainingCohortItem(
                    feature.symbol(), status, feature, labels, missing,
                    missing.isEmpty()
                            ? "All approved swing horizons have deterministic future outcomes."
                            : "One or more outcome dates lack a governed candle."));
        }

        List<SwingBenchmarkOutcome> benchmarks = benchmarks(outcomeDates, initialItems);
        Map<Integer, BigDecimal> benchmarkReturns = benchmarks.stream()
                .filter(benchmark -> benchmark.equalWeightGrossReturnPercent() != null)
                .collect(java.util.stream.Collectors.toMap(
                        SwingBenchmarkOutcome::horizonSessions,
                        SwingBenchmarkOutcome::equalWeightGrossReturnPercent));
        List<SwingTrainingCohortItem> items = initialItems.stream()
                .map(item -> withBenchmarks(item, benchmarkReturns))
                .sorted(Comparator.comparing(SwingTrainingCohortItem::symbol))
                .toList();
        int fullyLabeled = count(items, "LABELED");
        int rightCensored = count(items, "RIGHT_CENSORED");
        if (fullyLabeled + rightCensored != features.eligibleCount()) {
            throw new IllegalStateException("Eligible feature and label classifications do not reconcile.");
        }
        String manifestHash = manifestHasher.hash(
                features.universeSnapshotId(), asOf, labelThrough,
                features.manifestHash(), assumedRoundTripCostBps, benchmarks, items);
        long elapsedSeconds = (System.nanoTime() - startedAt) / 1_000_000_000L;
        LOGGER.info("Swing training preview completed: asOf={}, labelThrough={}, instruments={}, "
                        + "labeled={}, rightCensored={}, elapsedSeconds={}",
                asOf, labelThrough, items.size(), fullyLabeled, rightCensored, elapsedSeconds);

        return new SwingTrainingDatasetPreview(
                "REVIEW_REQUIRED",
                DATASET_CONTRACT_VERSION,
                FeaturePreviewService.FEATURE_SET_VERSION,
                asOf,
                labelThrough,
                features.universeSnapshotId(),
                features.universeObservedOn(),
                features.manifestHash(),
                features.instrumentCount(),
                features.eligibleCount(),
                fullyLabeled,
                rightCensored,
                features.insufficientHistoryCount(),
                features.staleCount(),
                features.noEligibleDataCount(),
                HORIZONS,
                assumedRoundTripCostBps,
                BENCHMARK_DEFINITION,
                benchmarks,
                HISTORICAL_MEMBERSHIP_STATUS,
                true,
                false,
                features.pointInTimeSafe(),
                labelsSeparated(asOf, items),
                manifestHash,
                false,
                0,
                0,
                0,
                items,
                "The label contract is reviewable, but current-snapshot membership causes survivor bias."
        );
    }

    private FutureCandleSet loadFutureCandles(
            FeatureUniversePreview features,
            LocalDate asOf,
            LocalDate labelThrough
    ) {
        Map<String, List<FeatureCandle>> bySymbol = new HashMap<>();
        Map<LocalDate, Set<String>> symbolsByDate = new HashMap<>();
        jdbcTemplate.query(connection -> {
            var statement = connection.prepareStatement(FUTURE_CANDLES_SQL);
            statement.setObject(1, features.universeSnapshotId());
            statement.setDate(2, Date.valueOf(asOf));
            statement.setDate(3, Date.valueOf(labelThrough));
            statement.setFetchSize(1_000);
            statement.setQueryTimeout(600);
            return statement;
        }, (RowCallbackHandler) resultSet -> {
            String symbol = resultSet.getString("source_symbol");
            LocalDate tradingDate = resultSet.getObject("trading_date", LocalDate.class);
            bySymbol.computeIfAbsent(symbol, ignored -> new ArrayList<>()).add(new FeatureCandle(
                    tradingDate,
                    resultSet.getString("source_code"),
                    resultSet.getBigDecimal("open_price"),
                    resultSet.getBigDecimal("high_price"),
                    resultSet.getBigDecimal("low_price"),
                    resultSet.getBigDecimal("close_price"),
                    resultSet.getBigDecimal("volume"),
                    resultSet.getBoolean("excluded")));
            symbolsByDate.computeIfAbsent(tradingDate, ignored -> new HashSet<>()).add(symbol);
        });
        int minimumSessionCoverage = (int) Math.ceil(features.instrumentCount() * 0.80);
        List<LocalDate> marketSessions = symbolsByDate.entrySet().stream()
                .filter(entry -> entry.getValue().size() >= minimumSessionCoverage)
                .map(Map.Entry::getKey)
                .sorted()
                .toList();
        return new FutureCandleSet(Map.copyOf(bySymbol), marketSessions);
    }

    private Map<Integer, LocalDate> outcomeDates(List<LocalDate> marketSessions) {
        Map<Integer, LocalDate> result = new LinkedHashMap<>();
        for (int horizon : HORIZONS) {
            if (marketSessions.size() >= horizon) {
                result.put(horizon, marketSessions.get(horizon - 1));
            }
        }
        return result;
    }

    private List<SwingBenchmarkOutcome> benchmarks(
            Map<Integer, LocalDate> outcomeDates,
            List<SwingTrainingCohortItem> items
    ) {
        List<SwingBenchmarkOutcome> result = new ArrayList<>();
        for (int horizon : HORIZONS) {
            List<BigDecimal> returns = items.stream()
                    .flatMap(item -> item.labels().stream())
                    .filter(label -> label.horizonSessions() == horizon)
                    .map(SwingOutcomeLabel::grossReturnPercent)
                    .toList();
            BigDecimal average = returns.isEmpty() ? null : returns.stream()
                    .reduce(BigDecimal.ZERO, BigDecimal::add)
                    .divide(BigDecimal.valueOf(returns.size()), 6, RoundingMode.HALF_UP);
            result.add(new SwingBenchmarkOutcome(
                    horizon, outcomeDates.get(horizon), returns.size(), average));
        }
        return List.copyOf(result);
    }

    private SwingTrainingCohortItem withBenchmarks(
            SwingTrainingCohortItem item,
            Map<Integer, BigDecimal> benchmarkReturns
    ) {
        List<SwingOutcomeLabel> labels = item.labels().stream()
                .map(label -> benchmarkReturns.containsKey(label.horizonSessions())
                        ? label.withBenchmark(benchmarkReturns.get(label.horizonSessions()))
                        : label)
                .toList();
        return new SwingTrainingCohortItem(
                item.symbol(), item.status(), item.featureInput(), labels,
                item.missingHorizons(), item.detail());
    }

    private void validateRequest(LocalDate asOf, LocalDate labelThrough, int costBps) {
        if (asOf == null || labelThrough == null) {
            throw new IllegalArgumentException("As-of and label-through dates are required.");
        }
        if (!labelThrough.isAfter(asOf)) {
            throw new IllegalArgumentException("The label-through date must be after the as-of date.");
        }
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Kolkata"));
        if (!labelThrough.isBefore(today)) {
            throw new IllegalArgumentException("The label-through date must be a completed prior India date.");
        }
        if (costBps < 0 || costBps > MAXIMUM_COST_BPS) {
            throw new IllegalArgumentException("Assumed round-trip cost must be between 0 and 1000 bps.");
        }
    }

    private void validateFeaturePreview(FeatureUniversePreview features, LocalDate asOf) {
        if (!"REVIEW_REQUIRED".equals(features.status())
                || !FeaturePreviewService.FEATURE_SET_VERSION.equals(features.featureSetVersion())
                || !asOf.equals(features.requestedAsOf())
                || features.instrumentCount() != 500
                || features.instruments().size() != 500
                || !features.pointInTimeSafe()
                || features.databaseWritesPerformed()) {
            throw new IllegalStateException("The point-in-time feature cohort failed its governed checkpoints.");
        }
    }

    private boolean labelsSeparated(LocalDate asOf, List<SwingTrainingCohortItem> items) {
        return items.stream().flatMap(item -> item.labels().stream())
                .allMatch(label -> label.outcomeDate().isAfter(asOf));
    }

    private int count(List<SwingTrainingCohortItem> items, String status) {
        return (int) items.stream().filter(item -> status.equals(item.status())).count();
    }

    private record FutureCandleSet(
            Map<String, List<FeatureCandle>> candlesBySymbol,
            List<LocalDate> marketSessions
    ) {
    }
}
