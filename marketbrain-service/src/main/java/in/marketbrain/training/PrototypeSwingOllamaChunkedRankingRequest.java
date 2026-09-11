package in.marketbrain.training;

import java.util.UUID;

public record PrototypeSwingOllamaChunkedRankingRequest(
        UUID datasetRunId,
        String model,
        Integer totalCandidateLimit,
        Integer chunkSize,
        Integer finalistsPerChunk,
        Integer maxRetriesPerChunk,
        Integer rankingHorizonSessions
) {
}
