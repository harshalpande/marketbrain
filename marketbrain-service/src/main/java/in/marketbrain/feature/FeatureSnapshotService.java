package in.marketbrain.feature;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.UUID;

@Service
public class FeatureSnapshotService {

    private final JdbcTemplate jdbcTemplate;
    private final FeatureUniversePreviewService previewService;
    private final FeatureUniverseManifestHasher manifestHasher;

    public FeatureSnapshotService(
            JdbcTemplate jdbcTemplate,
            FeatureUniversePreviewService previewService,
            FeatureUniverseManifestHasher manifestHasher
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.previewService = previewService;
        this.manifestHasher = manifestHasher;
    }

    @Transactional
    public synchronized FeatureSnapshotSummary persist(FeatureSnapshotRequest request) {
        validateRequest(request);
        FeatureUniversePreview analysis = previewService.preview(request.asOf());
        validateAnalysis(analysis, request.asOf(), request.expectedManifestHash());

        PersistedRun existing = findRun(analysis.universeSnapshotId(), request.asOf());
        if (existing != null) {
            requireSameReview(existing, request);
            return summary(existing.id(), false, 0, 0,
                    "The exact reviewed feature snapshot was already persisted.");
        }

        StateCounts stateBefore = stateCounts();
        UUID runId = UUID.randomUUID();
        int persistedFeatures = analysis.eligibleCount();
        int withheld = analysis.instrumentCount() - persistedFeatures;
        jdbcTemplate.update("""
                INSERT INTO feature_snapshot_run
                    (id, universe_snapshot_id, requested_as_of, feature_set_version,
                     source_manifest_hash, status, reviewed_by, instrument_count,
                     persisted_feature_count, withheld_count)
                VALUES (?, ?, ?, ?, ?, 'WRITING', ?, ?, ?, ?)
                """, runId, analysis.universeSnapshotId(), Date.valueOf(request.asOf()),
                analysis.featureSetVersion(), analysis.manifestHash(), request.reviewedBy().trim(),
                analysis.instrumentCount(), persistedFeatures, withheld);

        Map<String, Long> instrumentIds = instrumentIds(analysis.universeSnapshotId());
        for (FeaturePreview item : analysis.instruments()) {
            Long instrumentId = instrumentIds.get(item.symbol().toUpperCase(Locale.ROOT));
            if (instrumentId == null) {
                throw new IllegalStateException("No current universe instrument exists for " + item.symbol() + ".");
            }
            persistItem(runId, instrumentId, item);
        }

        Integer itemCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM feature_snapshot_item WHERE run_id = ?", Integer.class, runId);
        if (itemCount == null || itemCount != analysis.instrumentCount()) {
            throw new IllegalStateException("The complete reviewed feature snapshot was not persisted atomically.");
        }
        int completedRuns = jdbcTemplate.update("""
                UPDATE feature_snapshot_run
                SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = 'WRITING'
                """, runId);
        if (completedRuns != 1) {
            throw new IllegalStateException("The reviewed feature snapshot did not complete atomically.");
        }

        StateCounts stateAfter = stateCounts();
        int signalsCreated = stateAfter.signals() - stateBefore.signals();
        int ordersCreated = stateAfter.orders() - stateBefore.orders();
        if (signalsCreated != 0 || ordersCreated != 0) {
            throw new IllegalStateException("Feature persistence unexpectedly changed trading state.");
        }
        return summary(runId, true, signalsCreated, ordersCreated,
                "The complete reviewed TECHNICAL_V1 snapshot was persisted atomically.");
    }

    @Transactional(readOnly = true)
    public FeatureSnapshotQuality quality(UUID runId, String expectedManifestHash) {
        requireHash(expectedManifestHash);
        PersistedRun run = findRunById(runId);
        if (run == null) {
            throw new NoSuchElementException("No feature snapshot exists for run " + runId + ".");
        }
        if (!"COMPLETED".equals(run.status())) {
            throw new IllegalStateException("The feature snapshot is not completed.");
        }
        if (!run.sourceManifestHash().equals(expectedManifestHash)) {
            throw new IllegalStateException("The expected manifest does not match the persisted snapshot.");
        }

        List<FeaturePreview> reconstructed = reconstructedItems(run);
        String recomputedHash = manifestHasher.hash(
                run.universeSnapshotId(), run.requestedAsOf(), reconstructed);
        QualityCounts counts = qualityCounts(run.id());
        boolean manifestMatches = run.sourceManifestHash().equals(recomputedHash);
        boolean eligible = reconstructed.size() == run.instrumentCount()
                && counts.itemCount() == run.instrumentCount()
                && counts.completeVectors() == run.persistedFeatureCount()
                && counts.insufficientHistory() == run.withheldCount()
                && counts.stale() == 0
                && counts.noData() == 0
                && counts.partialVectorViolations() == 0
                && counts.withheldVectorViolations() == 0
                && manifestMatches;
        return new FeatureSnapshotQuality(
                eligible ? "ELIGIBLE" : "REVIEW_REQUIRED",
                run.id(), run.requestedAsOf(), run.featureSetVersion(), run.sourceManifestHash(),
                recomputedHash, run.instrumentCount(), run.persistedFeatureCount(), run.withheldCount(),
                counts.itemCount(), counts.completeVectors(), counts.insufficientHistory(),
                counts.stale(), counts.noData(), counts.partialVectorViolations(),
                counts.withheldVectorViolations(), manifestMatches, false,
                eligible
                        ? "Every persisted vector and withheld classification matches the reviewed manifest."
                        : "One or more persisted feature-snapshot invariants differ."
        );
    }

    private void validateRequest(FeatureSnapshotRequest request) {
        if (request == null || request.asOf() == null) {
            throw new IllegalArgumentException("An as-of date is required.");
        }
        requireHash(request.expectedManifestHash());
        if (request.reviewedBy() == null || request.reviewedBy().isBlank()
                || request.reviewedBy().trim().length() > 120) {
            throw new IllegalArgumentException("A reviewer name of at most 120 characters is required.");
        }
    }

    private void requireHash(String manifestHash) {
        if (manifestHash == null || !manifestHash.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("A lowercase 64-character manifest hash is required.");
        }
    }

    private void validateAnalysis(
            FeatureUniversePreview analysis,
            java.time.LocalDate requestedAsOf,
            String expectedManifestHash
    ) {
        if (!"REVIEW_REQUIRED".equals(analysis.status())
                || !FeaturePreviewService.FEATURE_SET_VERSION.equals(analysis.featureSetVersion())
                || !requestedAsOf.equals(analysis.requestedAsOf())
                || analysis.universeSnapshotId() == null
                || analysis.instrumentCount() != 500
                || analysis.instruments().size() != 500
                || analysis.databaseWritesPerformed()
                || !analysis.pointInTimeSafe()) {
            throw new IllegalStateException("The live feature analysis failed its governed pre-write checkpoints.");
        }
        if (!expectedManifestHash.equals(analysis.manifestHash())) {
            throw new IllegalStateException("The live feature manifest no longer matches the reviewed manifest.");
        }
        if (analysis.staleCount() != 0 || analysis.noEligibleDataCount() != 0) {
            throw new IllegalStateException("Stale or no-data instruments cannot enter this feature snapshot.");
        }
        if (analysis.eligibleCount() + analysis.staleCount()
                + analysis.insufficientHistoryCount() + analysis.noEligibleDataCount()
                != analysis.instrumentCount()
                || analysis.featureVectorCount() != analysis.eligibleCount() + analysis.staleCount()) {
            throw new IllegalStateException("The live feature classification counts are inconsistent.");
        }
        int eligible = 0;
        int stale = 0;
        int insufficient = 0;
        int noData = 0;
        long canonicalObservations = 0;
        long eligibleObservations = 0;
        long excludedObservations = 0;
        for (FeaturePreview item : analysis.instruments()) {
            if (!analysis.featureSetVersion().equals(item.featureSetVersion())
                    || !analysis.requestedAsOf().equals(item.requestedAsOf())
                    || !item.pointInTimeSafe() || item.databaseWritesPerformed()
                    || item.canonicalObservationCount() < 0
                    || item.eligibleObservationCount() < 0
                    || item.excludedObservationCount() < 0
                    || item.eligibleObservationCount() + item.excludedObservationCount()
                    != item.canonicalObservationCount()
                    || (item.effectiveAsOf() != null
                    && item.effectiveAsOf().isAfter(analysis.requestedAsOf()))) {
                throw new IllegalStateException("A feature classification failed its point-in-time invariants.");
            }
            switch (item.status()) {
                case "ELIGIBLE" -> {
                    eligible++;
                    if (!analysis.requestedAsOf().equals(item.effectiveAsOf())
                            || item.latestCandle() == null || !complete(item.features())) {
                        throw new IllegalStateException(
                                "An eligible feature vector is incomplete for " + item.symbol() + ".");
                    }
                }
                case "STALE" -> {
                    stale++;
                    if (item.effectiveAsOf() == null
                            || !item.effectiveAsOf().isBefore(analysis.requestedAsOf())
                            || item.latestCandle() == null || !complete(item.features())) {
                        throw new IllegalStateException("A stale feature classification is inconsistent.");
                    }
                }
                case "INSUFFICIENT_HISTORY" -> {
                    insufficient++;
                    if (item.effectiveAsOf() == null || item.latestCandle() == null
                            || item.eligibleObservationCount() >= FeaturePreviewService.MINIMUM_OBSERVATIONS
                            || item.features() != null) {
                        throw new IllegalStateException(
                                "An insufficient-history classification is inconsistent.");
                    }
                }
                case "NO_ELIGIBLE_DATA" -> {
                    noData++;
                    if (item.effectiveAsOf() != null || item.latestCandle() != null
                            || item.eligibleObservationCount() != 0 || item.features() != null) {
                        throw new IllegalStateException("A no-data classification is inconsistent.");
                    }
                }
                default -> throw new IllegalStateException("An unsupported feature classification was returned.");
            }
            canonicalObservations += item.canonicalObservationCount();
            eligibleObservations += item.eligibleObservationCount();
            excludedObservations += item.excludedObservationCount();
        }
        if (eligible != analysis.eligibleCount() || stale != analysis.staleCount()
                || insufficient != analysis.insufficientHistoryCount()
                || noData != analysis.noEligibleDataCount()
                || canonicalObservations != analysis.canonicalObservationCount()
                || eligibleObservations != analysis.eligibleObservationCount()
                || excludedObservations != analysis.excludedObservationCount()) {
            throw new IllegalStateException("The feature item totals do not match the reviewed analysis.");
        }
    }

    private boolean complete(FeatureValues values) {
        return values != null
                && values.previousClose() != null && values.dailyReturnPercent() != null
                && values.sma20() != null && values.sma50() != null && values.sma200() != null
                && values.ema12() != null && values.ema26() != null
                && values.rsi14() != null && values.atr14() != null
                && values.annualizedVolatility20Percent() != null
                && values.volumeRatio20() != null && values.rangePosition252Percent() != null;
    }

    private Map<String, Long> instrumentIds(UUID snapshotId) {
        Map<String, Long> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT source_symbol, instrument_id
                FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'MATCHED'
                """, (org.springframework.jdbc.core.RowCallbackHandler) resultSet -> result.put(
                        resultSet.getString("source_symbol").toUpperCase(Locale.ROOT),
                        resultSet.getLong("instrument_id")), snapshotId);
        return result;
    }

    private void persistItem(UUID runId, long instrumentId, FeaturePreview item) {
        FeaturePreview.LatestCandle latest = item.latestCandle();
        FeatureValues values = "ELIGIBLE".equals(item.status()) ? item.features() : null;
        jdbcTemplate.update("""
                INSERT INTO feature_snapshot_item
                    (run_id, instrument_id, symbol, classification, effective_as_of,
                     canonical_observation_count, eligible_observation_count, excluded_observation_count,
                     latest_source, latest_open, latest_high, latest_low, latest_close, latest_volume,
                     previous_close, daily_return_percent, sma20, sma50, sma200, ema12, ema26,
                     rsi14, atr14, annualized_volatility20_percent, volume_ratio20,
                     range_position252_percent)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, runId, instrumentId, item.symbol(), item.status(), dateOrNull(item.effectiveAsOf()),
                item.canonicalObservationCount(), item.eligibleObservationCount(), item.excludedObservationCount(),
                latest == null ? null : latest.source(), latest == null ? null : latest.open(),
                latest == null ? null : latest.high(), latest == null ? null : latest.low(),
                latest == null ? null : latest.close(), latest == null ? null : latest.volume(),
                value(values, FeatureValues::previousClose), value(values, FeatureValues::dailyReturnPercent),
                value(values, FeatureValues::sma20), value(values, FeatureValues::sma50),
                value(values, FeatureValues::sma200), value(values, FeatureValues::ema12),
                value(values, FeatureValues::ema26), value(values, FeatureValues::rsi14),
                value(values, FeatureValues::atr14),
                value(values, FeatureValues::annualizedVolatility20Percent),
                value(values, FeatureValues::volumeRatio20),
                value(values, FeatureValues::rangePosition252Percent));
    }

    private BigDecimal value(FeatureValues values, java.util.function.Function<FeatureValues, BigDecimal> getter) {
        return values == null ? null : getter.apply(values);
    }

    private Date dateOrNull(java.time.LocalDate value) {
        return value == null ? null : Date.valueOf(value);
    }

    private PersistedRun findRun(UUID snapshotId, java.time.LocalDate asOf) {
        List<PersistedRun> runs = jdbcTemplate.query("""
                SELECT id, universe_snapshot_id, requested_as_of, feature_set_version,
                       source_manifest_hash, status, reviewed_by, instrument_count,
                       persisted_feature_count, withheld_count
                FROM feature_snapshot_run
                WHERE universe_snapshot_id = ? AND requested_as_of = ? AND feature_set_version = ?
                """, this::mapRun, snapshotId, Date.valueOf(asOf), FeaturePreviewService.FEATURE_SET_VERSION);
        return runs.isEmpty() ? null : runs.getFirst();
    }

    private PersistedRun findRunById(UUID runId) {
        List<PersistedRun> runs = jdbcTemplate.query("""
                SELECT id, universe_snapshot_id, requested_as_of, feature_set_version,
                       source_manifest_hash, status, reviewed_by, instrument_count,
                       persisted_feature_count, withheld_count
                FROM feature_snapshot_run WHERE id = ?
                """, this::mapRun, runId);
        return runs.isEmpty() ? null : runs.getFirst();
    }

    private PersistedRun mapRun(java.sql.ResultSet resultSet, int row) throws java.sql.SQLException {
        return new PersistedRun(
                resultSet.getObject("id", UUID.class),
                resultSet.getObject("universe_snapshot_id", UUID.class),
                resultSet.getObject("requested_as_of", java.time.LocalDate.class),
                resultSet.getString("feature_set_version"),
                resultSet.getString("source_manifest_hash"), resultSet.getString("status"),
                resultSet.getString("reviewed_by"), resultSet.getInt("instrument_count"),
                resultSet.getInt("persisted_feature_count"), resultSet.getInt("withheld_count"));
    }

    private void requireSameReview(PersistedRun run, FeatureSnapshotRequest request) {
        if (!"COMPLETED".equals(run.status())
                || !run.sourceManifestHash().equals(request.expectedManifestHash())
                || !run.reviewedBy().equals(request.reviewedBy().trim())) {
            throw new IllegalStateException("A different or incomplete feature snapshot already owns this scope.");
        }
    }

    private FeatureSnapshotSummary summary(
            UUID runId,
            boolean writesPerformed,
            int signalsCreated,
            int ordersCreated,
            String detail
    ) {
        PersistedRun run = findRunById(runId);
        QualityCounts counts = qualityCounts(runId);
        return new FeatureSnapshotSummary(
                run.status(), run.id(), run.universeSnapshotId(), run.requestedAsOf(),
                run.featureSetVersion(), run.sourceManifestHash(), run.reviewedBy(),
                run.instrumentCount(), run.persistedFeatureCount(), run.withheldCount(),
                counts.insufficientHistory(), counts.stale(), counts.noData(), counts.itemCount(),
                signalsCreated, ordersCreated, writesPerformed, detail);
    }

    private QualityCounts qualityCounts(UUID runId) {
        return jdbcTemplate.queryForObject("""
                SELECT COUNT(*) AS item_count,
                       COUNT(*) FILTER (WHERE classification = 'ELIGIBLE') AS complete_vectors,
                       COUNT(*) FILTER (WHERE classification = 'INSUFFICIENT_HISTORY') AS insufficient_history,
                       COUNT(*) FILTER (WHERE classification = 'STALE') AS stale,
                       COUNT(*) FILTER (WHERE classification = 'NO_ELIGIBLE_DATA') AS no_data,
                       COUNT(*) FILTER (
                           WHERE classification = 'ELIGIBLE' AND (
                               previous_close IS NULL OR daily_return_percent IS NULL
                               OR sma20 IS NULL OR sma50 IS NULL OR sma200 IS NULL
                               OR ema12 IS NULL OR ema26 IS NULL OR rsi14 IS NULL OR atr14 IS NULL
                               OR annualized_volatility20_percent IS NULL OR volume_ratio20 IS NULL
                               OR range_position252_percent IS NULL
                           )
                       ) AS partial_vector_violations,
                       COUNT(*) FILTER (
                           WHERE classification <> 'ELIGIBLE' AND (
                               previous_close IS NOT NULL OR daily_return_percent IS NOT NULL
                               OR sma20 IS NOT NULL OR sma50 IS NOT NULL OR sma200 IS NOT NULL
                               OR ema12 IS NOT NULL OR ema26 IS NOT NULL OR rsi14 IS NOT NULL OR atr14 IS NOT NULL
                               OR annualized_volatility20_percent IS NOT NULL OR volume_ratio20 IS NOT NULL
                               OR range_position252_percent IS NOT NULL
                           )
                       ) AS withheld_vector_violations
                FROM feature_snapshot_item WHERE run_id = ?
                """, (resultSet, row) -> new QualityCounts(
                        resultSet.getInt("item_count"), resultSet.getInt("complete_vectors"),
                        resultSet.getInt("insufficient_history"), resultSet.getInt("stale"),
                        resultSet.getInt("no_data"), resultSet.getInt("partial_vector_violations"),
                        resultSet.getInt("withheld_vector_violations")), runId);
    }

    private List<FeaturePreview> reconstructedItems(PersistedRun run) {
        return jdbcTemplate.query("""
                SELECT symbol, classification, effective_as_of,
                       canonical_observation_count, eligible_observation_count, excluded_observation_count,
                       latest_source, latest_open, latest_high, latest_low, latest_close, latest_volume,
                       previous_close, daily_return_percent, sma20, sma50, sma200, ema12, ema26,
                       rsi14, atr14, annualized_volatility20_percent, volume_ratio20,
                       range_position252_percent
                FROM feature_snapshot_item WHERE run_id = ? ORDER BY symbol
                """, (resultSet, row) -> {
            String classification = resultSet.getString("classification");
            FeaturePreview.LatestCandle latest = resultSet.getString("latest_source") == null ? null
                    : new FeaturePreview.LatestCandle(
                            resultSet.getString("latest_source"), resultSet.getBigDecimal("latest_open"),
                            resultSet.getBigDecimal("latest_high"), resultSet.getBigDecimal("latest_low"),
                            resultSet.getBigDecimal("latest_close"), resultSet.getBigDecimal("latest_volume"));
            FeatureValues values = "ELIGIBLE".equals(classification) ? new FeatureValues(
                    resultSet.getBigDecimal("previous_close"), resultSet.getBigDecimal("daily_return_percent"),
                    resultSet.getBigDecimal("sma20"), resultSet.getBigDecimal("sma50"),
                    resultSet.getBigDecimal("sma200"), resultSet.getBigDecimal("ema12"),
                    resultSet.getBigDecimal("ema26"), resultSet.getBigDecimal("rsi14"),
                    resultSet.getBigDecimal("atr14"),
                    resultSet.getBigDecimal("annualized_volatility20_percent"),
                    resultSet.getBigDecimal("volume_ratio20"),
                    resultSet.getBigDecimal("range_position252_percent")) : null;
            return new FeaturePreview(
                    classification, resultSet.getString("symbol"), run.featureSetVersion(),
                    run.requestedAsOf(), resultSet.getObject("effective_as_of", java.time.LocalDate.class),
                    resultSet.getInt("canonical_observation_count"),
                    resultSet.getInt("eligible_observation_count"),
                    resultSet.getInt("excluded_observation_count"), latest, values,
                    true, false, "Reconstructed from immutable feature snapshot.");
        }, run.id());
    }

    private StateCounts stateCounts() {
        return jdbcTemplate.queryForObject("""
                SELECT (SELECT COUNT(*) FROM market_signal) AS signals,
                       (SELECT COUNT(*) FROM paper_order) AS orders
                """, (resultSet, row) -> new StateCounts(
                        resultSet.getInt("signals"), resultSet.getInt("orders")));
    }

    private record PersistedRun(
            UUID id,
            UUID universeSnapshotId,
            java.time.LocalDate requestedAsOf,
            String featureSetVersion,
            String sourceManifestHash,
            String status,
            String reviewedBy,
            int instrumentCount,
            int persistedFeatureCount,
            int withheldCount
    ) {
    }

    private record QualityCounts(
            int itemCount,
            int completeVectors,
            int insufficientHistory,
            int stale,
            int noData,
            int partialVectorViolations,
            int withheldVectorViolations
    ) {
    }

    private record StateCounts(int signals, int orders) {
    }
}
