package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaRankingPreview(
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
        int rankingHorizonSessions,
        String promptHash,
        String responseHash,
        String prompt,
        String ollamaResponse,
        List<PrototypeSwingOllamaCandidate> candidates,
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
