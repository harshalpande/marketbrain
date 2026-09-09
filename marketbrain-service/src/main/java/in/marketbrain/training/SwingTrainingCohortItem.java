package in.marketbrain.training;

import in.marketbrain.feature.FeaturePreview;

import java.util.List;

public record SwingTrainingCohortItem(
        String symbol,
        String status,
        FeaturePreview featureInput,
        List<SwingOutcomeLabel> labels,
        List<Integer> missingHorizons,
        String detail
) {
}
