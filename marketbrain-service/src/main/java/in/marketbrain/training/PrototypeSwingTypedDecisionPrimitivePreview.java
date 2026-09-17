package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingTypedDecisionPrimitivePreview(
        String status,
        UUID datasetRunId,
        LocalDate asOf,
        LocalDate labelThrough,
        String selectionMode,
        int startOffset,
        int candidateLimit,
        int candidateCount,
        int rankingHorizonSessions,
        String decisionContractVersion,
        String grammarVersion,
        String grammar,
        List<String> allowedDecisions,
        List<String> allowedRiskBuckets,
        List<String> allowedTrapFlags,
        List<String> allowedScoreBands,
        List<String> allowedConfidenceBands,
        List<String> allowedReasonCodes,
        List<PrototypeSwingTypedDecisionPrimitiveCandidate> candidates,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int llamaCppCallCount,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
