package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaChunkedRankingAttempt(
        int chunkNumber,
        int attemptNumber,
        String repairInstruction,
        List<String> expectedCandidateIds,
        List<String> candidateSymbols,
        String promptHash,
        int promptCharacterCount,
        String responseHash,
        int responseCharacterCount,
        long ollamaElapsedMillis,
        long ollamaTotalDurationNanos,
        int ollamaPromptEvalCount,
        int ollamaEvalCount,
        String ollamaResponse,
        boolean responseParseableJson,
        boolean responseSchemaValid,
        String rankingQualityStatus,
        String scoreCalibrationStatus,
        List<String> responseValidationFailures,
        List<String> evaluationFailures,
        List<String> calibrationFailures,
        boolean acceptedForChunkSummary
) {
}
