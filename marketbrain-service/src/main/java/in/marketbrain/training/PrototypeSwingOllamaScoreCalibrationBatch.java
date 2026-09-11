package in.marketbrain.training;

import java.math.BigDecimal;
import java.util.List;

public record PrototypeSwingOllamaScoreCalibrationBatch(
        int candidateLimit,
        int candidateCount,
        boolean responseParseableJson,
        boolean responseSchemaValid,
        String rankingQualityStatus,
        String scoreCalibrationStatus,
        Integer minimumScore,
        Integer maximumScore,
        Integer scoreSpread,
        BigDecimal scoreRankCorrelation,
        String topScoreSymbol,
        Integer topScoreActualRank,
        BigDecimal topScoreNetReturnPercent,
        String bestActualSymbol,
        Integer bestActualScore,
        BigDecimal bestActualNetReturnPercent,
        int highConfidenceMissCount,
        int negativeReturnTopThreeCount,
        int weakReasonCount,
        List<String> calibrationFailures,
        PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluationPreview
) {
}
