package in.marketbrain.training;

import java.util.UUID;

public record PrototypeSwingOllamaRankingRequest(
        UUID datasetRunId,
        String model,
        Integer candidateLimit,
        Integer rankingHorizonSessions,
        String repairInstruction
) {
    public PrototypeSwingOllamaRankingRequest(
            UUID datasetRunId,
            String model,
            Integer candidateLimit,
            Integer rankingHorizonSessions
    ) {
        this(datasetRunId, model, candidateLimit, rankingHorizonSessions, null);
    }
}
