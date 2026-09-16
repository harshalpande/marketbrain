package in.marketbrain.training;

import java.util.List;

public record PrototypeSwingOllamaIntelligenceScorecardDimension(
        String name,
        int scorePercent,
        String status,
        List<String> evidence
) {
}
