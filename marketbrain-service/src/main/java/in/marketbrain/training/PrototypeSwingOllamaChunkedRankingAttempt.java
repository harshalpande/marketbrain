package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaChunkedRankingAttempt(
        int chunkNumber,
        int attemptNumber,
        List<String> expectedCandidateIds,
        List<String> candidateSymbols,
        String responseHash,
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
