package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record SwingTrainingDatasetPreview(
        String status,
        String datasetContractVersion,
        String featureSetVersion,
        LocalDate asOf,
        LocalDate labelThrough,
        UUID universeSnapshotId,
        LocalDate universeObservedOn,
        String inputFeatureManifestHash,
        int instrumentCount,
        int featureEligibleCount,
        int fullyLabeledCount,
        int rightCensoredCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        List<Integer> horizonsSessions,
        int assumedRoundTripCostBps,
        String benchmarkDefinition,
        List<SwingBenchmarkOutcome> benchmarkOutcomes,
        String historicalMembershipStatus,
        boolean survivorshipBiasPresent,
        boolean trainingEligible,
        boolean pointInTimeSafe,
        boolean futureLabelsSeparated,
        String manifestHash,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        List<SwingTrainingCohortItem> instruments,
        String detail
) {
}
