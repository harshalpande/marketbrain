package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaChunkedRankingChunk(
        int chunkNumber,
        int offset,
        int candidateCount,
        List<String> candidateSymbols,
        String chunkStatus,
        int attemptCount,
        int acceptedAttemptNumber,
        List<PrototypeSwingOllamaChunkedRankingAttempt> attempts,
        List<PrototypeSwingOllamaChunkedRankingFinalist> finalists,
        PrototypeSwingOllamaScoreCalibrationBatch acceptedCalibrationBatch
) {
}
