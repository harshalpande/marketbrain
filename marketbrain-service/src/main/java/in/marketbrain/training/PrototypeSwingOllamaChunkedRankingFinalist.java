package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingOllamaChunkedRankingFinalist(
        int chunkNumber,
        String symbol,
        int chunkOllamaRank,
        int chunkActualRank,
        int ollamaScore,
        String ollamaConfidence,
        BigDecimal targetNetReturnPercent,
        BigDecimal targetBenchmarkExcessReturnPercent,
        BigDecimal targetMaximumDrawdownPercent,
        String qualityBucket,
        String reason
) {
}
