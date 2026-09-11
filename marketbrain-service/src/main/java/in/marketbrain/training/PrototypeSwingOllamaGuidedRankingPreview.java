package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaGuidedRankingPreview(
        String status,
        UUID datasetRunId,
        String datasetContractVersion,
        String sourceUniverseCode,
        LocalDate asOf,
        LocalDate labelThrough,
        String datasetManifestHash,
        String model,
        int candidateLimit,
        int candidateCount,
        int trainingExampleCount,
        int rankingHorizonSessions,
        String instructionPackVersion,
        String responseSchemaVersion,
        String rubricVersion,
        String playbookHash,
        String promptHash,
        String responseHash,
        String prompt,
        String ollamaResponse,
        List<PrototypeSwingOllamaTrainingExample> trainingExamples,
        List<PrototypeSwingOllamaCandidate> candidates,
        boolean responseParseableJson,
        boolean responseSchemaValid,
        List<String> responseValidationFailures,
        boolean dailyFreshDataFeedbackLoopDesigned,
        boolean dailyFreshDataUsedForTraining,
        boolean survivorshipRiskPresent,
        boolean prototypeTrainingEligible,
        boolean benchmarkTrainingEligible,
        boolean pointInTimeSafe,
        boolean futureLabelsSeparated,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
