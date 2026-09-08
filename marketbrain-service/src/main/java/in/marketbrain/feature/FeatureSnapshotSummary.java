package in.marketbrain.feature;

import java.time.LocalDate;
import java.util.UUID;

public record FeatureSnapshotSummary(
        String status,
        UUID runId,
        UUID universeSnapshotId,
        LocalDate requestedAsOf,
        String featureSetVersion,
        String sourceManifestHash,
        String reviewedBy,
        int instrumentCount,
        int persistedFeatureCount,
        int withheldCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        int persistedItemCount,
        int signalsCreated,
        int ordersCreated,
        boolean databaseWritesPerformed,
        String detail
) {
}
