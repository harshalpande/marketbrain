package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingOllamaCandidateEvaluation(
        String symbol,
        int ollamaRank,
        int javaBaselineRank,
        int finalReviewRank,
        int actualRank,
        int rankError,
        int ollamaScore,
        int javaBaselineScore,
        int finalReviewScore,
        String ollamaConfidence,
        String javaBaselineBucket,
        int rankDeviationFromJavaBaseline,
        String arbitrationDecision,
        String javaBaselineReason,
        String arbitrationReason,
        BigDecimal targetNetReturnPercent,
        BigDecimal targetBenchmarkExcessReturnPercent,
        BigDecimal targetMaximumDrawdownPercent,
        String qualityBucket,
        boolean highConfidenceMiss,
        boolean topThreeNegativeReturn,
        boolean reasonMentionsKnownFeature,
        String reason
) {
}
