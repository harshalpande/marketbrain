package in.marketbrain.feature;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record DailyFeatureAutomationPreview(
        String status,
        LocalDate targetDate,
        UUID universeSnapshotId,
        UUID dailyRunId,
        String dailyRunStatus,
        String dailyManifestHash,
        int dailyInstrumentCount,
        int totalChunks,
        int completedChunks,
        int failedChunks,
        long acceptedRows,
        long rejectedRows,
        int targetDateCandleCount,
        String dailyQualityStatus,
        int blockingInstrumentCount,
        int missingProviderDataInstrumentCount,
        int reviewInstrumentCount,
        int duplicateRowCount,
        int invalidRowCount,
        int unresolvedFindingCount,
        int truncatedFindingCount,
        String featureSetVersion,
        String featureManifestHash,
        int featureInstrumentCount,
        int eligibleCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        String persistenceAction,
        UUID existingFeatureSnapshotRunId,
        String existingFeatureSnapshotStatus,
        List<String> failedCheckpoints,
        boolean pointInTimeSafe,
        boolean databaseWritesPerformed,
        String detail
) {
}
