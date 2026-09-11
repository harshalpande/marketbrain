package in.marketbrain.training;

import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaScoreCalibrationRequest(
        UUID datasetRunId,
        String model,
        List<Integer> candidateLimits,
        Integer rankingHorizonSessions
) {
}
