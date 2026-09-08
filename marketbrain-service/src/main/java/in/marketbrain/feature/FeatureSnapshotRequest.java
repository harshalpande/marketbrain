package in.marketbrain.feature;

import java.time.LocalDate;

public record FeatureSnapshotRequest(
        LocalDate asOf,
        String expectedManifestHash,
        String reviewedBy
) {
}
