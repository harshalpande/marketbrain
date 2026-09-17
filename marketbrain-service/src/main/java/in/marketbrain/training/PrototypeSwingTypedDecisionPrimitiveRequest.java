package in.marketbrain.training;

import java.util.UUID;

public record PrototypeSwingTypedDecisionPrimitiveRequest(
        UUID datasetRunId,
        String selectionMode,
        Integer startOffset,
        Integer candidateLimit,
        Integer rankingHorizonSessions
) {
}
