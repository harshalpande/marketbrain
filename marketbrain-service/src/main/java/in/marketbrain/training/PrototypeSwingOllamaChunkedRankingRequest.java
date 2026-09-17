package in.marketbrain.training;

import java.util.UUID;

public record PrototypeSwingOllamaChunkedRankingRequest(
        UUID datasetRunId,
        String model,
        String selectionMode,
        Integer startOffset,
        Integer totalCandidateLimit,
        Integer chunkSize,
        Integer finalistsPerChunk,
        Integer maxRetriesPerChunk,
        Integer rankingHorizonSessions
) {
    public PrototypeSwingOllamaChunkedRankingRequest(
            UUID datasetRunId,
            String model,
            Integer startOffset,
            Integer totalCandidateLimit,
            Integer chunkSize,
            Integer finalistsPerChunk,
            Integer maxRetriesPerChunk,
            Integer rankingHorizonSessions
    ) {
        this(datasetRunId, model, null, startOffset, totalCandidateLimit, chunkSize,
                finalistsPerChunk, maxRetriesPerChunk, rankingHorizonSessions);
    }
}
