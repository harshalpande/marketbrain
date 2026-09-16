package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaIntelligenceScorecardChunk(
        int chunkNumber,
        String chunkStatus,
        int candidateCount,
        int attemptCount,
        int acceptedAttemptNumber,
        String acceptedRankingQualityStatus,
        String acceptedScoreCalibrationStatus,
        boolean acceptedSchemaValid,
        int intelligenceScorePercent,
        String topFinalistSymbol,
        int topFinalistActualRank,
        int finalistCount,
        List<String> warnings
) {
}
