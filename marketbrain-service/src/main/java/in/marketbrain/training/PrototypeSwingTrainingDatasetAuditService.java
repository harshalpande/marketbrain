package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class PrototypeSwingTrainingDatasetAuditService {

    private final JdbcTemplate jdbcTemplate;

    public PrototypeSwingTrainingDatasetAuditService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional(readOnly = true)
    public PrototypeSwingTrainingDatasetAudit audit(UUID requestedRunId) {
        UUID runId = requestedRunId == null ? latestRunId() : requestedRunId;
        DatasetRun run = loadRun(runId);
        List<PrototypeSwingTrainingClassificationAudit> classifications = classificationCounts(runId);
        List<PrototypeSwingTrainingHorizonAudit> horizons = horizonAudits(runId);
        List<PrototypeSwingTrainingExtremeOutcome> best = extremeOutcomes(runId, true);
        List<PrototypeSwingTrainingExtremeOutcome> worst = extremeOutcomes(runId, false);
        List<String> failed = failedCheckpoints(run, horizons);

        return new PrototypeSwingTrainingDatasetAudit(
                failed.isEmpty() ? "REVIEW_REQUIRED" : "REVIEW_BLOCKED",
                run.id(),
                run.datasetContractVersion(),
                run.sourceUniverseCode(),
                run.asOf(),
                run.labelThrough(),
                run.datasetManifestHash(),
                run.assumedRoundTripCostBps(),
                run.benchmarkDefinition(),
                run.historicalMembershipStatus(),
                run.instrumentCount(),
                run.featureEligibleCount(),
                run.fullyLabeledCount(),
                run.rightCensoredCount(),
                run.insufficientHistoryCount(),
                run.staleCount(),
                run.noEligibleDataCount(),
                run.persistedItemCount(),
                run.persistedLabelCount(),
                SwingTrainingDatasetPreviewService.HORIZONS,
                classifications,
                horizons,
                best,
                worst,
                run.survivorshipRiskPresent(),
                run.prototypeTrainingEligible(),
                run.benchmarkTrainingEligible(),
                run.pointInTimeSafe(),
                run.futureLabelsSeparated(),
                failed.isEmpty(),
                false,
                0,
                0,
                0,
                failed,
                failed.isEmpty()
                        ? "The persisted prototype dataset is internally consistent and ready for read-only "
                        + "Ollama-assisted ranking experiments."
                        : "The persisted prototype dataset has audit checkpoint failures that must be reviewed."
        );
    }

    private UUID latestRunId() {
        List<UUID> ids = jdbcTemplate.query("""
                SELECT id
                FROM prototype_swing_training_dataset_run
                WHERE status = 'COMPLETED'
                ORDER BY created_at DESC, as_of DESC, label_through DESC
                LIMIT 1
                """, (resultSet, row) -> resultSet.getObject("id", UUID.class));
        if (ids.isEmpty()) {
            throw new IllegalStateException("No completed prototype swing-training dataset run is available.");
        }
        return ids.getFirst();
    }

    private DatasetRun loadRun(UUID runId) {
        List<DatasetRun> runs = jdbcTemplate.query("""
                SELECT *
                FROM prototype_swing_training_dataset_run
                WHERE id = ?
                """, (resultSet, row) -> new DatasetRun(
                        resultSet.getObject("id", UUID.class),
                        resultSet.getString("dataset_contract_version"),
                        resultSet.getString("source_universe_code"),
                        resultSet.getObject("as_of", LocalDate.class),
                        resultSet.getObject("label_through", LocalDate.class),
                        resultSet.getString("dataset_manifest_hash"),
                        resultSet.getInt("assumed_round_trip_cost_bps"),
                        resultSet.getString("benchmark_definition"),
                        resultSet.getString("historical_membership_status"),
                        resultSet.getInt("instrument_count"),
                        resultSet.getInt("feature_eligible_count"),
                        resultSet.getInt("fully_labeled_count"),
                        resultSet.getInt("right_censored_count"),
                        resultSet.getInt("insufficient_history_count"),
                        resultSet.getInt("stale_count"),
                        resultSet.getInt("no_eligible_data_count"),
                        resultSet.getInt("persisted_item_count"),
                        resultSet.getInt("persisted_label_count"),
                        resultSet.getBoolean("survivorship_risk_present"),
                        resultSet.getBoolean("prototype_training_eligible"),
                        resultSet.getBoolean("benchmark_training_eligible"),
                        resultSet.getBoolean("point_in_time_safe"),
                        resultSet.getBoolean("future_labels_separated")), runId);
        if (runs.isEmpty()) {
            throw new IllegalArgumentException("The requested prototype swing-training dataset run was not found.");
        }
        return runs.getFirst();
    }

    private List<PrototypeSwingTrainingClassificationAudit> classificationCounts(UUID runId) {
        return jdbcTemplate.query("""
                SELECT classification, COUNT(*)::integer AS item_count
                FROM prototype_swing_training_dataset_item
                WHERE run_id = ?
                GROUP BY classification
                ORDER BY classification
                """, (resultSet, row) -> new PrototypeSwingTrainingClassificationAudit(
                        resultSet.getString("classification"),
                        resultSet.getInt("item_count")), runId);
    }

    private List<PrototypeSwingTrainingHorizonAudit> horizonAudits(UUID runId) {
        return jdbcTemplate.query("""
                SELECT label.horizon_sessions,
                       COUNT(*)::integer AS label_count,
                       MIN(label.outcome_date) AS earliest_outcome_date,
                       MAX(label.outcome_date) AS latest_outcome_date,
                       AVG(label.gross_return_percent)::numeric(20,6) AS average_gross_return_percent,
                       PERCENTILE_CONT(0.5) WITHIN GROUP (
                           ORDER BY label.gross_return_percent
                       )::numeric(20,6) AS median_gross_return_percent,
                       AVG(label.net_return_percent)::numeric(20,6) AS average_net_return_percent,
                       PERCENTILE_CONT(0.5) WITHIN GROUP (
                           ORDER BY label.net_return_percent
                       )::numeric(20,6) AS median_net_return_percent,
                       MIN(label.net_return_percent)::numeric(20,6) AS minimum_net_return_percent,
                       MAX(label.net_return_percent)::numeric(20,6) AS maximum_net_return_percent,
                       COUNT(*) FILTER (WHERE label.net_return_percent > 0)::integer AS positive_count,
                       COUNT(*) FILTER (WHERE label.net_return_percent < 0)::integer AS negative_count,
                       (
                           COUNT(*) FILTER (WHERE label.net_return_percent > 0) * 100.0 / COUNT(*)
                       )::numeric(20,6) AS positive_percent,
                       COUNT(*) FILTER (
                           WHERE label.benchmark_excess_return_percent > 0
                       )::integer AS benchmark_outperform_count,
                       (
                           COUNT(*) FILTER (WHERE label.benchmark_excess_return_percent > 0) * 100.0 / COUNT(*)
                       )::numeric(20,6) AS benchmark_outperform_percent,
                       AVG(label.benchmark_excess_return_percent)::numeric(20,6)
                           AS average_benchmark_excess_return_percent,
                       AVG(label.maximum_favorable_excursion_percent)::numeric(20,6)
                           AS average_maximum_favorable_excursion_percent,
                       AVG(label.maximum_adverse_excursion_percent)::numeric(20,6)
                           AS average_maximum_adverse_excursion_percent,
                       AVG(label.maximum_drawdown_percent)::numeric(20,6)
                           AS average_maximum_drawdown_percent
                FROM prototype_swing_training_dataset_label label
                JOIN prototype_swing_training_dataset_item item ON item.id = label.item_id
                WHERE item.run_id = ?
                GROUP BY label.horizon_sessions
                ORDER BY label.horizon_sessions
                """, (resultSet, row) -> new PrototypeSwingTrainingHorizonAudit(
                        resultSet.getInt("horizon_sessions"),
                        resultSet.getInt("label_count"),
                        resultSet.getObject("earliest_outcome_date", LocalDate.class),
                        resultSet.getObject("latest_outcome_date", LocalDate.class),
                        resultSet.getBigDecimal("average_gross_return_percent"),
                        resultSet.getBigDecimal("median_gross_return_percent"),
                        resultSet.getBigDecimal("average_net_return_percent"),
                        resultSet.getBigDecimal("median_net_return_percent"),
                        resultSet.getBigDecimal("minimum_net_return_percent"),
                        resultSet.getBigDecimal("maximum_net_return_percent"),
                        resultSet.getInt("positive_count"),
                        resultSet.getInt("negative_count"),
                        resultSet.getBigDecimal("positive_percent"),
                        resultSet.getInt("benchmark_outperform_count"),
                        resultSet.getBigDecimal("benchmark_outperform_percent"),
                        resultSet.getBigDecimal("average_benchmark_excess_return_percent"),
                        resultSet.getBigDecimal("average_maximum_favorable_excursion_percent"),
                        resultSet.getBigDecimal("average_maximum_adverse_excursion_percent"),
                        resultSet.getBigDecimal("average_maximum_drawdown_percent")), runId);
    }

    private List<PrototypeSwingTrainingExtremeOutcome> extremeOutcomes(UUID runId, boolean best) {
        List<PrototypeSwingTrainingExtremeOutcome> result = new ArrayList<>();
        String direction = best ? "DESC" : "ASC";
        for (int horizon : SwingTrainingDatasetPreviewService.HORIZONS) {
            result.addAll(jdbcTemplate.query(("""
                    SELECT label.horizon_sessions, item.symbol, label.outcome_date,
                           label.gross_return_percent, label.net_return_percent,
                           label.benchmark_excess_return_percent,
                           label.maximum_favorable_excursion_percent,
                           label.maximum_adverse_excursion_percent,
                           label.maximum_drawdown_percent
                    FROM prototype_swing_training_dataset_label label
                    JOIN prototype_swing_training_dataset_item item ON item.id = label.item_id
                    WHERE item.run_id = ? AND label.horizon_sessions = ?
                    ORDER BY label.net_return_percent %s,
                             item.symbol
                    LIMIT 5
                    """).formatted(direction), (resultSet, row) -> new PrototypeSwingTrainingExtremeOutcome(
                            resultSet.getInt("horizon_sessions"),
                            resultSet.getString("symbol"),
                            resultSet.getObject("outcome_date", LocalDate.class),
                            resultSet.getBigDecimal("gross_return_percent"),
                            resultSet.getBigDecimal("net_return_percent"),
                            resultSet.getBigDecimal("benchmark_excess_return_percent"),
                            resultSet.getBigDecimal("maximum_favorable_excursion_percent"),
                            resultSet.getBigDecimal("maximum_adverse_excursion_percent"),
                            resultSet.getBigDecimal("maximum_drawdown_percent")),
                    runId, horizon));
        }
        return List.copyOf(result);
    }

    private List<String> failedCheckpoints(
            DatasetRun run,
            List<PrototypeSwingTrainingHorizonAudit> horizons
    ) {
        List<String> failed = new ArrayList<>();
        if (!PrototypeSwingTrainingDatasetService.DATASET_CONTRACT_VERSION.equals(run.datasetContractVersion())) {
            failed.add("DATASET_CONTRACT_VERSION");
        }
        if (!PrototypeSwingTrainingDatasetService.SOURCE_UNIVERSE_CODE.equals(run.sourceUniverseCode())) {
            failed.add("SOURCE_UNIVERSE_CODE");
        }
        if (run.persistedItemCount() != run.instrumentCount()) {
            failed.add("ITEM_COUNT_RECONCILIATION");
        }
        if (run.persistedLabelCount() != run.fullyLabeledCount() * SwingTrainingDatasetPreviewService.HORIZONS.size()) {
            failed.add("LABEL_COUNT_RECONCILIATION");
        }
        if (horizons.size() != SwingTrainingDatasetPreviewService.HORIZONS.size()) {
            failed.add("HORIZON_COVERAGE");
        }
        for (PrototypeSwingTrainingHorizonAudit horizon : horizons) {
            if (!SwingTrainingDatasetPreviewService.HORIZONS.contains(horizon.horizonSessions())
                    || horizon.labelCount() != run.fullyLabeledCount()) {
                failed.add("HORIZON_" + horizon.horizonSessions() + "_LABEL_COUNT");
            }
        }
        if (!run.survivorshipRiskPresent() || !run.prototypeTrainingEligible()
                || run.benchmarkTrainingEligible() || !run.pointInTimeSafe()
                || !run.futureLabelsSeparated()) {
            failed.add("GOVERNANCE_FLAGS");
        }
        return List.copyOf(failed);
    }

    private record DatasetRun(
            UUID id,
            String datasetContractVersion,
            String sourceUniverseCode,
            LocalDate asOf,
            LocalDate labelThrough,
            String datasetManifestHash,
            int assumedRoundTripCostBps,
            String benchmarkDefinition,
            String historicalMembershipStatus,
            int instrumentCount,
            int featureEligibleCount,
            int fullyLabeledCount,
            int rightCensoredCount,
            int insufficientHistoryCount,
            int staleCount,
            int noEligibleDataCount,
            int persistedItemCount,
            int persistedLabelCount,
            boolean survivorshipRiskPresent,
            boolean prototypeTrainingEligible,
            boolean benchmarkTrainingEligible,
            boolean pointInTimeSafe,
            boolean futureLabelsSeparated
    ) {
    }
}
