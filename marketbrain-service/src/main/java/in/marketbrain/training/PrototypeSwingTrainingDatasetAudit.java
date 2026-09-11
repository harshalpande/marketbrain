package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingTrainingDatasetAudit(
        String status,
        UUID datasetRunId,
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
        List<Integer> horizonsSessions,
        List<PrototypeSwingTrainingClassificationAudit> classificationCounts,
        List<PrototypeSwingTrainingHorizonAudit> horizonAudits,
        List<PrototypeSwingTrainingExtremeOutcome> bestOutcomes,
        List<PrototypeSwingTrainingExtremeOutcome> worstOutcomes,
        boolean survivorshipRiskPresent,
        boolean prototypeTrainingEligible,
        boolean benchmarkTrainingEligible,
        boolean pointInTimeSafe,
        boolean futureLabelsSeparated,
        boolean auditReadyForOllamaRanking,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        List<String> failedCheckpoints,
        String detail
) {
}
