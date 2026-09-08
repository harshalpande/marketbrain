package in.marketbrain.feature;

import java.time.LocalDate;
import java.util.UUID;

public record FeatureSnapshotQuality(
        String status,
        UUID runId,
        LocalDate requestedAsOf,
        String featureSetVersion,
        String sourceManifestHash,
        String recomputedManifestHash,
        int instrumentCount,
        int persistedFeatureCount,
        int withheldCount,
        int persistedItemCount,
        int completeVectorCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        int partialVectorViolationCount,
        int withheldVectorViolationCount,
        boolean manifestMatches,
        boolean databaseWritesPerformed,
        String detail
) {
}
