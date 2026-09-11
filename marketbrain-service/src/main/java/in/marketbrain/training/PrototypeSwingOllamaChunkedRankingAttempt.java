package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaChunkedRankingAttempt(
        int chunkNumber,
        int attemptNumber,
        List<String> candidateSymbols,
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
