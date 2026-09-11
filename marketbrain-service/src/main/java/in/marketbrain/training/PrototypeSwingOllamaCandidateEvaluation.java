package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingOllamaCandidateEvaluation(
        String symbol,
        int ollamaRank,
        int actualRank,
        int rankError,
        int ollamaScore,
        String ollamaConfidence,
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
