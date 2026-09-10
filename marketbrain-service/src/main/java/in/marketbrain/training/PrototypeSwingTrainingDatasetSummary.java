package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingTrainingDatasetSummary(
        String status,
        String persistenceAction,
        UUID datasetRunId,
        String datasetContractVersion,
        String sourceUniverseCode,
        LocalDate asOf,
        LocalDate labelThrough,
        UUID universeSnapshotId,
        String featureSetVersion,
        String inputFeatureManifestHash,
        String datasetManifestHash,
        int assumedRoundTripCostBps,
        String benchmarkDefinition,
        String historicalMembershipStatus,
        String reviewedBy,
        int instrumentCount,
        int featureEligibleCount,
        int fullyLabeledCount,
        int rightCensoredCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        int persistedItemCount,
        int persistedLabelCount,
        List<Integer> horizonsSessions,
        boolean survivorshipRiskPresent,
        boolean prototypeTrainingEligible,
        boolean benchmarkTrainingEligible,
        boolean pointInTimeSafe,
        boolean futureLabelsSeparated,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        List<String> failedCheckpoints,
        String detail
) {
}
