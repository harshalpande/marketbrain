package in.marketbrain.feature;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record FeatureUniversePreview(
        String status,
        String featureSetVersion,
        LocalDate requestedAsOf,
        UUID universeSnapshotId,
        LocalDate universeObservedOn,
        int instrumentCount,
        int eligibleCount,
        int staleCount,
        int insufficientHistoryCount,
        int noEligibleDataCount,
        int featureVectorCount,
        long canonicalObservationCount,
        long eligibleObservationCount,
        long excludedObservationCount,
        String manifestHash,
        boolean pointInTimeSafe,
        boolean databaseWritesPerformed,
        List<FeaturePreview> instruments,
        String detail
) {
}
