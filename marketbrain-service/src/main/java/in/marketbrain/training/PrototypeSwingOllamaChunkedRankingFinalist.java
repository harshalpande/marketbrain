package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingOllamaChunkedRankingFinalist(
        int chunkNumber,
        String symbol,
        int chunkOllamaRank,
        int chunkJavaBaselineRank,
        int chunkFinalReviewRank,
        int chunkActualRank,
        int ollamaScore,
        int javaBaselineScore,
        int finalReviewScore,
        String ollamaConfidence,
        String arbitrationDecision,
        BigDecimal targetNetReturnPercent,
        BigDecimal targetBenchmarkExcessReturnPercent,
        BigDecimal targetMaximumDrawdownPercent,
        String qualityBucket,
        String javaBaselineReason,
        String arbitrationReason,
        String reason
) {
}
