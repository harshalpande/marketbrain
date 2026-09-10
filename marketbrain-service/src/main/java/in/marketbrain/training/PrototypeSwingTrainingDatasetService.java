package in.marketbrain.training;

import in.marketbrain.feature.FeaturePreview;
import in.marketbrain.feature.FeatureValues;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.sql.PreparedStatement;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;

@Service
public class PrototypeSwingTrainingDatasetService {

    public static final String DATASET_CONTRACT_VERSION = "PROTOTYPE_SWING_TRAINING_DATASET_V1";
    public static final String SOURCE_UNIVERSE_CODE = "CURRENT_SNAPSHOT_PROTOTYPE";
    private static final Logger LOGGER = LoggerFactory.getLogger(PrototypeSwingTrainingDatasetService.class);
    private static final int MAXIMUM_COST_BPS = 1_000;

    private final JdbcTemplate jdbcTemplate;
    private final SwingTrainingDatasetPreviewService previewService;

    public PrototypeSwingTrainingDatasetService(
            JdbcTemplate jdbcTemplate,
            SwingTrainingDatasetPreviewService previewService
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.previewService = previewService;
    }

    @Transactional(timeout = 1_800)
    public PrototypeSwingTrainingDatasetSummary persist(
            LocalDate asOf,
            LocalDate labelThrough,
            int assumedRoundTripCostBps,
            String expectedManifestHash,
            String reviewedBy
    ) {
        validateRequest(asOf, labelThrough, assumedRoundTripCostBps, expectedManifestHash, reviewedBy);
        SwingTrainingDatasetPreview preview =
                previewService.preview(asOf, labelThrough, assumedRoundTripCostBps);
        validatePreview(preview, expectedManifestHash);

        PersistedRun existing = findExisting(preview);
        if (existing != null) {
            return summary(existing.id(), "ALREADY_PERSISTED", false,
                    "The exact manifest-bound prototype swing-training dataset already exists.");
        }

        UUID runId = UUID.randomUUID();
        try {
            LOGGER.info("Prototype swing-training dataset persistence started: asOf={}, labelThrough={}, "
                            + "items={}, labels={}, manifest={}",
                    asOf, labelThrough, preview.instrumentCount(), labelCount(preview), preview.manifestHash());
            persistRun(runId, preview, reviewedBy.trim());
            Map<String, Long> instrumentIds = instrumentIds(preview.universeSnapshotId());
            int itemCount = 0;
            int labelCount = 0;
            for (SwingTrainingCohortItem item : preview.instruments()) {
                Long instrumentId = instrumentIds.get(item.symbol().toUpperCase(Locale.ROOT));
                if (instrumentId == null) {
                    throw new IllegalStateException("No instrument mapping is available for " + item.symbol() + ".");
                }
                long itemId = persistItem(runId, instrumentId, item);
                itemCount++;
                for (SwingOutcomeLabel label : item.labels()) {
                    persistLabel(itemId, label);
                    labelCount++;
                }
                if (itemCount % 50 == 0 || itemCount == preview.instrumentCount()) {
                    LOGGER.info("Prototype swing-training dataset persistence progress: {}/{} items, {} labels",
                            itemCount, preview.instrumentCount(), labelCount);
                }
            }
            validatePersistedCounts(runId, itemCount, labelCount);
        } catch (DuplicateKeyException duplicate) {
            PersistedRun duplicateRun = findExisting(preview);
            if (duplicateRun == null) {
                throw duplicate;
            }
            return summary(duplicateRun.id(), "ALREADY_PERSISTED", false,
                    "The exact manifest-bound prototype swing-training dataset already exists.");
        }

        LOGGER.info("Prototype swing-training dataset persisted: runId={}, asOf={}, labelThrough={}, "
                        + "items={}, labels={}, manifest={}",
                runId, asOf, labelThrough, preview.instrumentCount(),
                preview.instruments().stream().mapToInt(item -> item.labels().size()).sum(),
                preview.manifestHash());
        return summary(runId, "CREATED", true,
                "The prototype current-snapshot swing-training dataset was persisted immutably.");
    }

    private void validateRequest(
            LocalDate asOf,
            LocalDate labelThrough,
            int assumedRoundTripCostBps,
            String expectedManifestHash,
            String reviewedBy
    ) {
        if (asOf == null) {
            throw new IllegalArgumentException("asOf is required.");
        }
        if (labelThrough == null || !labelThrough.isAfter(asOf)) {
            throw new IllegalArgumentException("labelThrough must be after asOf.");
        }
        if (assumedRoundTripCostBps < 0 || assumedRoundTripCostBps > MAXIMUM_COST_BPS) {
            throw new IllegalArgumentException("assumedRoundTripCostBps must be between 0 and 1000.");
        }
        if (expectedManifestHash == null || !expectedManifestHash.matches("^[0-9a-fA-F]{64}$")) {
            throw new IllegalArgumentException("expectedManifestHash must contain 64 hexadecimal characters.");
        }
        if (reviewedBy == null || reviewedBy.isBlank()) {
            throw new IllegalArgumentException("reviewedBy is required.");
        }
    }

    private void validatePreview(SwingTrainingDatasetPreview preview, String expectedManifestHash) {
        if (!preview.manifestHash().equals(expectedManifestHash.toLowerCase(Locale.ROOT))) {
            throw new IllegalArgumentException("The current preview does not match expectedManifestHash.");
        }
        if (!"REVIEW_REQUIRED".equals(preview.status())
                || !"SWING_TRAINING_V1".equals(preview.datasetContractVersion())
                || !"TECHNICAL_V1".equals(preview.featureSetVersion())
                || preview.fullyLabeledCount() <= 0
                || !preview.survivorshipBiasPresent()
                || preview.trainingEligible()
                || !preview.pointInTimeSafe()
                || !preview.futureLabelsSeparated()
                || preview.databaseWritesPerformed()
                || preview.ollamaCallCount() != 0
                || preview.signalsCreated() != 0
                || preview.ordersCreated() != 0) {
            throw new IllegalStateException("The swing preview is not eligible for prototype persistence.");
        }
    }

    private void persistRun(UUID runId, SwingTrainingDatasetPreview preview, String reviewedBy) {
        jdbcTemplate.update("""
                INSERT INTO prototype_swing_training_dataset_run
                    (id, dataset_contract_version, source_universe_code, as_of, label_through,
                     universe_snapshot_id, feature_set_version, input_feature_manifest_hash,
                     dataset_manifest_hash, assumed_round_trip_cost_bps, benchmark_definition,
                     historical_membership_status, status, reviewed_by, instrument_count,
                     feature_eligible_count, fully_labeled_count, right_censored_count,
                     insufficient_history_count, stale_count, no_eligible_data_count,
                     persisted_item_count, persisted_label_count, survivorship_risk_present,
                     prototype_training_eligible, benchmark_training_eligible, point_in_time_safe,
                     future_labels_separated)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                runId, DATASET_CONTRACT_VERSION, SOURCE_UNIVERSE_CODE,
                Date.valueOf(preview.asOf()), Date.valueOf(preview.labelThrough()),
                preview.universeSnapshotId(), preview.featureSetVersion(), preview.inputFeatureManifestHash(),
                preview.manifestHash(), preview.assumedRoundTripCostBps(), preview.benchmarkDefinition(),
                preview.historicalMembershipStatus(), reviewedBy, preview.instrumentCount(),
                preview.featureEligibleCount(), preview.fullyLabeledCount(), preview.rightCensoredCount(),
                preview.insufficientHistoryCount(), preview.staleCount(), preview.noEligibleDataCount(),
                preview.instrumentCount(), labelCount(preview), preview.survivorshipBiasPresent(),
                true, false, preview.pointInTimeSafe(), preview.futureLabelsSeparated());
    }

    private long persistItem(UUID runId, long instrumentId, SwingTrainingCohortItem item) {
        FeaturePreview feature = item.featureInput();
        FeaturePreview.LatestCandle latest = feature.latestCandle();
        FeatureValues values = feature.features();
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement("""
                    INSERT INTO prototype_swing_training_dataset_item
                        (run_id, instrument_id, symbol, classification, effective_as_of, missing_horizons,
                         latest_source, latest_open, latest_high, latest_low, latest_close, latest_volume,
                         previous_close, daily_return_percent, sma20, sma50, sma200, ema12, ema26,
                         rsi14, atr14, annualized_volatility20_percent, volume_ratio20,
                         range_position252_percent, detail)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, new String[]{"id"});
            statement.setObject(1, runId);
            statement.setLong(2, instrumentId);
            statement.setString(3, item.symbol());
            statement.setString(4, item.status());
            statement.setObject(5, feature.effectiveAsOf() == null ? null : Date.valueOf(feature.effectiveAsOf()));
            statement.setString(6, missingHorizons(item.missingHorizons()));
            statement.setString(7, latest == null ? null : latest.source());
            statement.setBigDecimal(8, latest == null ? null : latest.open());
            statement.setBigDecimal(9, latest == null ? null : latest.high());
            statement.setBigDecimal(10, latest == null ? null : latest.low());
            statement.setBigDecimal(11, latest == null ? null : latest.close());
            statement.setBigDecimal(12, latest == null ? null : latest.volume());
            statement.setBigDecimal(13, value(values, FeatureValues::previousClose));
            statement.setBigDecimal(14, value(values, FeatureValues::dailyReturnPercent));
            statement.setBigDecimal(15, value(values, FeatureValues::sma20));
            statement.setBigDecimal(16, value(values, FeatureValues::sma50));
            statement.setBigDecimal(17, value(values, FeatureValues::sma200));
            statement.setBigDecimal(18, value(values, FeatureValues::ema12));
            statement.setBigDecimal(19, value(values, FeatureValues::ema26));
            statement.setBigDecimal(20, value(values, FeatureValues::rsi14));
            statement.setBigDecimal(21, value(values, FeatureValues::atr14));
            statement.setBigDecimal(22, value(values, FeatureValues::annualizedVolatility20Percent));
            statement.setBigDecimal(23, value(values, FeatureValues::volumeRatio20));
            statement.setBigDecimal(24, value(values, FeatureValues::rangePosition252Percent));
            statement.setString(25, item.detail());
            return statement;
        }, keyHolder);
        Number key = keyHolder.getKey();
        if (key == null) {
            throw new IllegalStateException("The persisted dataset item did not return an id.");
        }
        return key.longValue();
    }

    private void persistLabel(long itemId, SwingOutcomeLabel label) {
        jdbcTemplate.update("""
                INSERT INTO prototype_swing_training_dataset_label
                    (item_id, horizon_sessions, outcome_date, gross_return_percent,
                     assumed_round_trip_cost_percent, net_return_percent,
                     maximum_favorable_excursion_percent, maximum_adverse_excursion_percent,
                     maximum_drawdown_percent, benchmark_proxy_return_percent,
                     benchmark_excess_return_percent)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                itemId, label.horizonSessions(), Date.valueOf(label.outcomeDate()),
                label.grossReturnPercent(), label.assumedRoundTripCostPercent(),
                label.netReturnPercent(), label.maximumFavorableExcursionPercent(),
                label.maximumAdverseExcursionPercent(), label.maximumDrawdownPercent(),
                label.benchmarkProxyReturnPercent(), label.benchmarkExcessReturnPercent());
    }

    private Map<String, Long> instrumentIds(UUID universeSnapshotId) {
        Map<String, Long> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT source_symbol, instrument_id
                FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'MATCHED'
                """, (RowCallbackHandler) resultSet -> result.put(
                resultSet.getString("source_symbol").toUpperCase(Locale.ROOT),
                resultSet.getLong("instrument_id")), universeSnapshotId);
        return result;
    }

    private PersistedRun findExisting(SwingTrainingDatasetPreview preview) {
        List<PersistedRun> runs = jdbcTemplate.query("""
                SELECT id, dataset_manifest_hash
                FROM prototype_swing_training_dataset_run
                WHERE source_universe_code = ?
                  AND as_of = ?
                  AND label_through = ?
                  AND assumed_round_trip_cost_bps = ?
                  AND input_feature_manifest_hash = ?
                """, (resultSet, row) -> new PersistedRun(
                        resultSet.getObject("id", UUID.class),
                        resultSet.getString("dataset_manifest_hash")),
                SOURCE_UNIVERSE_CODE, Date.valueOf(preview.asOf()), Date.valueOf(preview.labelThrough()),
                preview.assumedRoundTripCostBps(), preview.inputFeatureManifestHash());
        if (runs.isEmpty()) {
            return null;
        }
        PersistedRun run = runs.getFirst();
        if (!run.datasetManifestHash().equals(preview.manifestHash())) {
            throw new IllegalStateException("A different prototype dataset manifest already owns this scope.");
        }
        return run;
    }

    private PrototypeSwingTrainingDatasetSummary summary(
            UUID runId,
            String persistenceAction,
            boolean databaseWritesPerformed,
            String detail
    ) {
        return jdbcTemplate.queryForObject("""
                SELECT run.*,
                       COUNT(DISTINCT item.id)::integer AS item_count,
                       COUNT(label.id)::integer AS label_count
                FROM prototype_swing_training_dataset_run run
                LEFT JOIN prototype_swing_training_dataset_item item ON item.run_id = run.id
                LEFT JOIN prototype_swing_training_dataset_label label ON label.item_id = item.id
                WHERE run.id = ?
                GROUP BY run.id
                """, (resultSet, row) -> new PrototypeSwingTrainingDatasetSummary(
                        resultSet.getString("status"),
                        persistenceAction,
                        resultSet.getObject("id", UUID.class),
                        resultSet.getString("dataset_contract_version"),
                        resultSet.getString("source_universe_code"),
                        resultSet.getObject("as_of", LocalDate.class),
                        resultSet.getObject("label_through", LocalDate.class),
                        resultSet.getObject("universe_snapshot_id", UUID.class),
                        resultSet.getString("feature_set_version"),
                        resultSet.getString("input_feature_manifest_hash"),
                        resultSet.getString("dataset_manifest_hash"),
                        resultSet.getInt("assumed_round_trip_cost_bps"),
                        resultSet.getString("benchmark_definition"),
                        resultSet.getString("historical_membership_status"),
                        resultSet.getString("reviewed_by"),
                        resultSet.getInt("instrument_count"),
                        resultSet.getInt("feature_eligible_count"),
                        resultSet.getInt("fully_labeled_count"),
                        resultSet.getInt("right_censored_count"),
                        resultSet.getInt("insufficient_history_count"),
                        resultSet.getInt("stale_count"),
                        resultSet.getInt("no_eligible_data_count"),
                        resultSet.getInt("item_count"),
                        resultSet.getInt("label_count"),
                        SwingTrainingDatasetPreviewService.HORIZONS,
                        resultSet.getBoolean("survivorship_risk_present"),
                        resultSet.getBoolean("prototype_training_eligible"),
                        resultSet.getBoolean("benchmark_training_eligible"),
                        resultSet.getBoolean("point_in_time_safe"),
                        resultSet.getBoolean("future_labels_separated"),
                        databaseWritesPerformed,
                        0,
                        0,
                        0,
                        List.of(),
                        detail), runId);
    }

    private void validatePersistedCounts(UUID runId, int expectedItems, int expectedLabels) {
        Counts counts = jdbcTemplate.queryForObject("""
                SELECT COUNT(DISTINCT item.id)::integer AS item_count,
                       COUNT(label.id)::integer AS label_count
                FROM prototype_swing_training_dataset_item item
                LEFT JOIN prototype_swing_training_dataset_label label ON label.item_id = item.id
                WHERE item.run_id = ?
                """, (resultSet, row) -> new Counts(
                        resultSet.getInt("item_count"), resultSet.getInt("label_count")), runId);
        if (counts == null || counts.items() != expectedItems || counts.labels() != expectedLabels) {
            throw new IllegalStateException("Persisted prototype dataset counts do not reconcile.");
        }
    }

    private int labelCount(SwingTrainingDatasetPreview preview) {
        return preview.instruments().stream().mapToInt(item -> item.labels().size()).sum();
    }

    private String missingHorizons(List<Integer> values) {
        if (values.isEmpty()) {
            return "";
        }
        List<String> text = new ArrayList<>();
        for (Integer value : values) {
            text.add(value.toString());
        }
        return String.join(",", text);
    }

    private java.math.BigDecimal value(
            FeatureValues values,
            Function<FeatureValues, java.math.BigDecimal> getter
    ) {
        return values == null ? null : getter.apply(values);
    }

    private record PersistedRun(UUID id, String datasetManifestHash) {
    }

    private record Counts(int items, int labels) {
    }
}
