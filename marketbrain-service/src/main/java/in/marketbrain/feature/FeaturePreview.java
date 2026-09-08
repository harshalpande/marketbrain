package in.marketbrain.feature;

import java.math.BigDecimal;
import java.time.LocalDate;

public record FeaturePreview(
        String status,
        String symbol,
        String featureSetVersion,
        LocalDate requestedAsOf,
        LocalDate effectiveAsOf,
        int canonicalObservationCount,
        int eligibleObservationCount,
        int excludedObservationCount,
        LatestCandle latestCandle,
        FeatureValues features,
        boolean pointInTimeSafe,
        boolean databaseWritesPerformed,
        String detail
) {
    public record LatestCandle(
            String source,
            BigDecimal open,
            BigDecimal high,
            BigDecimal low,
            BigDecimal close,
            BigDecimal volume
    ) {
    }
}
