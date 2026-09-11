package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaChunkedRankingPreview(
        String status,
        UUID datasetRunId,
        String model,
        LocalDate asOf,
        LocalDate labelThrough,
        int startOffset,
        int totalCandidateLimit,
        int chunkSize,
        int finalistsPerChunk,
        int maxRetriesPerChunk,
        int rankingHorizonSessions,
        String chunkedRankingVersion,
        int chunkCount,
        int passedChunkCount,
        int warningChunkCount,
        int failedChunkCount,
        int processedCandidateCount,
        int finalistCount,
        int ollamaCallCount,
        List<PrototypeSwingOllamaChunkedRankingChunk> chunks,
        List<PrototypeSwingOllamaChunkedRankingFinalist> mergedFinalists,
        List<String> aggregateFailures,
        boolean databaseWritesPerformed,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
