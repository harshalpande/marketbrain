package in.marketbrain.training;

import java.time.Instant;
import java.util.UUID;

public record PrototypeSwingOllamaChunkedRankingJobStatus(
        UUID jobId,
        String status,
        int progressPercent,
        int activeChunkNumber,
        int targetChunkCount,
        int completedChunkCount,
        int passedChunkCount,
        int failedChunkCount,
        String model,
        Instant submittedAt,
        Instant startedAt,
        Instant completedAt,
        String errorMessage,
        PrototypeSwingOllamaChunkedRankingPreview result,
        boolean databaseWritesPerformed,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
