package in.marketbrain.feature;

import in.marketbrain.marketdata.backfill.BackfillQualityReport;
import in.marketbrain.marketdata.backfill.BackfillQualityService;
import in.marketbrain.marketdata.daily.DailyEnrichmentRunSummary;
import in.marketbrain.marketdata.daily.DailyEnrichmentService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class DailyFeatureAutomationPreviewService {

    private static final int EXPECTED_UNIVERSE_SIZE = 500;

    private final JdbcTemplate jdbcTemplate;
    private final DailyEnrichmentService dailyEnrichmentService;
    private final BackfillQualityService qualityService;
    private final FeatureUniversePreviewService featurePreviewService;

    public DailyFeatureAutomationPreviewService(
            JdbcTemplate jdbcTemplate,
            DailyEnrichmentService dailyEnrichmentService,
            BackfillQualityService qualityService,
            FeatureUniversePreviewService featurePreviewService
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.dailyEnrichmentService = dailyEnrichmentService;
        this.qualityService = qualityService;
        this.featurePreviewService = featurePreviewService;
    }

    @Transactional(readOnly = true)
    public DailyFeatureAutomationPreview preview(LocalDate targetDate) {
        if (targetDate == null) {
            throw new IllegalArgumentException("A target date is required.");
        }
        DailyEnrichmentRunSummary dailyRun = dailyEnrichmentService.findForTarget(targetDate)
                .orElseThrow(() -> new IllegalStateException(
                        "No daily enrichment run exists for the current universe and target date."));
        BackfillQualityReport quality = qualityService.audit(dailyRun.runId(), false);
        FeatureUniversePreview features = featurePreviewService.preview(targetDate);
        int targetDateCandles = targetDateCandleCount(features.universeSnapshotId(), targetDate);
        PersistedFeatureSnapshot existing = existingSnapshot(
                features.universeSnapshotId(), targetDate, features.featureSetVersion());

        boolean dailyRunComplete = "COMPLETED".equals(dailyRun.status())
                && targetDate.equals(dailyRun.targetDate())
                && dailyRun.instruments() > 0
                && dailyRun.instruments() <= EXPECTED_UNIVERSE_SIZE
                && dailyRun.totalChunks() > 0
                && dailyRun.totalChunks() == dailyRun.instruments()
                && dailyRun.completedChunks() == dailyRun.totalChunks()
                && dailyRun.pendingChunks() == 0
                && dailyRun.runningChunks() == 0
                && dailyRun.retryChunks() == 0
                && dailyRun.failedChunks() == 0
                && dailyRun.acceptedRows() >= dailyRun.totalChunks()
                && dailyRun.rejectedRows() == 0;
        boolean databaseQualityComplete = "PASS".equals(quality.qualityStatus())
                && quality.jobId().equals(dailyRun.runId())
                && "COMPLETED".equals(quality.jobStatus())
                && targetDate.equals(quality.requestedTo())
                && quality.instrumentCount() == dailyRun.instruments()
                && quality.blockingInstrumentCount() == 0
                && quality.missingProviderDataInstrumentCount() == 0
                && quality.reviewInstrumentCount() == 0
                && quality.duplicateRows() == 0
                && quality.invalidRows() == 0
                && quality.unresolvedFindingCount() == 0
                && quality.truncatedFindingCount() == 0;
        boolean featureAnalysisComplete = "REVIEW_REQUIRED".equals(features.status())
                && FeaturePreviewService.FEATURE_SET_VERSION.equals(features.featureSetVersion())
                && features.instrumentCount() == EXPECTED_UNIVERSE_SIZE
                && features.instruments().size() == EXPECTED_UNIVERSE_SIZE
                && features.eligibleCount() + features.insufficientHistoryCount()
                + features.staleCount() + features.noEligibleDataCount() == EXPECTED_UNIVERSE_SIZE
                && features.featureVectorCount() == features.eligibleCount() + features.staleCount()
                && features.staleCount() == 0
                && features.noEligibleDataCount() == 0
                && features.pointInTimeSafe()
                && !features.databaseWritesPerformed();
        boolean sameUniverse = dailyRun.universeSnapshotId().equals(features.universeSnapshotId());
        boolean completeCoverage = targetDateCandles == EXPECTED_UNIVERSE_SIZE;
        boolean existingSnapshotSafe = existing == null
                || ("COMPLETED".equals(existing.status())
                && existing.manifestHash().equals(features.manifestHash()));
        List<String> failedCheckpoints = new ArrayList<>();
        if (!dailyRunComplete) {
            failedCheckpoints.add("DAILY_RUN");
        }
        if (!databaseQualityComplete) {
            failedCheckpoints.add("DATABASE_QUALITY");
        }
        if (!sameUniverse) {
            failedCheckpoints.add("UNIVERSE_ALIGNMENT");
        }
        if (!completeCoverage) {
            failedCheckpoints.add("TARGET_DATE_COVERAGE");
        }
        if (!featureAnalysisComplete) {
            failedCheckpoints.add("FEATURE_ANALYSIS");
        }
        if (!existingSnapshotSafe) {
            failedCheckpoints.add("EXISTING_SNAPSHOT");
        }
        boolean ready = dailyRunComplete && databaseQualityComplete
                && featureAnalysisComplete && sameUniverse
                && completeCoverage && existingSnapshotSafe;

        String persistenceAction;
        if (!ready) {
            persistenceAction = "REVIEW_REQUIRED";
        } else if (existing == null) {
            persistenceAction = "READY_TO_PERSIST";
        } else {
            persistenceAction = "ALREADY_PERSISTED";
        }
        return new DailyFeatureAutomationPreview(
                ready ? "READY" : "REVIEW_REQUIRED",
                targetDate,
                features.universeSnapshotId(),
                dailyRun.runId(),
                dailyRun.status(),
                dailyRun.manifestHash(),
                dailyRun.instruments(),
                dailyRun.totalChunks(),
                dailyRun.completedChunks(),
                dailyRun.failedChunks(),
                dailyRun.acceptedRows(),
                dailyRun.rejectedRows(),
                targetDateCandles,
                quality.qualityStatus(),
                quality.blockingInstrumentCount(),
                quality.missingProviderDataInstrumentCount(),
                quality.reviewInstrumentCount(),
                quality.duplicateRows(),
                quality.invalidRows(),
                quality.unresolvedFindingCount(),
                quality.truncatedFindingCount(),
                features.featureSetVersion(),
                features.manifestHash(),
                features.instrumentCount(),
                features.eligibleCount(),
                features.insufficientHistoryCount(),
                features.staleCount(),
                features.noEligibleDataCount(),
                persistenceAction,
                existing == null ? null : existing.id(),
                existing == null ? null : existing.status(),
                List.copyOf(failedCheckpoints),
                features.pointInTimeSafe(),
                false,
                ready
                        ? "The completed daily run, target-date coverage, and governed feature manifest align."
                        : "One or more daily-to-feature automation gates require review."
        );
    }

    private int targetDateCandleCount(UUID snapshotId, LocalDate targetDate) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(DISTINCT member.instrument_id)
                FROM universe_snapshot_member member
                JOIN market_candle candle
                  ON candle.instrument_id = member.instrument_id
                 AND candle.interval_code = 'days:1'
                 AND candle.is_complete = TRUE
                 AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date = ?
                JOIN market_data_source source
                  ON source.id = candle.source_id
                 AND source.code = 'UPSTOX'
                WHERE member.snapshot_id = ?
                  AND member.match_status = 'MATCHED'
                """, Integer.class, Date.valueOf(targetDate), snapshotId);
        return count == null ? 0 : count;
    }

    private PersistedFeatureSnapshot existingSnapshot(
            UUID snapshotId,
            LocalDate targetDate,
            String featureSetVersion
    ) {
        List<PersistedFeatureSnapshot> snapshots = jdbcTemplate.query("""
                SELECT id, status, source_manifest_hash
                FROM feature_snapshot_run
                WHERE universe_snapshot_id = ?
                  AND requested_as_of = ?
                  AND feature_set_version = ?
                """, (resultSet, row) -> new PersistedFeatureSnapshot(
                        resultSet.getObject("id", UUID.class),
                        resultSet.getString("status"),
                        resultSet.getString("source_manifest_hash")),
                snapshotId, Date.valueOf(targetDate), featureSetVersion);
        return snapshots.isEmpty() ? null : snapshots.getFirst();
    }

    private record PersistedFeatureSnapshot(UUID id, String status, String manifestHash) {
    }
}
