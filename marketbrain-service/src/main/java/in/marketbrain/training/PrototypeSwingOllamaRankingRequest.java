package in.marketbrain.training;

import java.util.UUID;

public record PrototypeSwingOllamaRankingRequest(
        UUID datasetRunId,
        String model,
        Integer candidateLimit,
        Integer rankingHorizonSessions
) {
}
