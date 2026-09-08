package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class FeatureUniverseManifestHasherTest {

    private final FeatureUniverseManifestHasher hasher = new FeatureUniverseManifestHasher();
    private final UUID snapshotId = UUID.fromString("83ec77aa-3a5a-4e03-8fab-5f7088b55cee");
    private final LocalDate asOf = LocalDate.of(2026, 9, 8);

    @Test
    void producesAStableHashAndChangesWhenAFeatureChanges() {
        FeaturePreview first = preview(new BigDecimal("100.000000"));
        FeaturePreview changed = preview(new BigDecimal("101.000000"));

        String hash = hasher.hash(snapshotId, asOf, List.of(first));

        assertThat(hash).hasSize(64).matches("[0-9a-f]{64}");
        assertThat(hasher.hash(snapshotId, asOf, List.of(first))).isEqualTo(hash);
        assertThat(hasher.hash(snapshotId, asOf, List.of(changed))).isNotEqualTo(hash);
    }

    private FeaturePreview preview(BigDecimal close) {
        FeatureValues values = new FeatureValues(
                close, BigDecimal.ONE, close, close, close, close, close,
                BigDecimal.valueOf(50), BigDecimal.ONE, BigDecimal.TEN,
                BigDecimal.ONE, BigDecimal.valueOf(50));
        return new FeaturePreview(
                "ELIGIBLE", "RELIANCE", "TECHNICAL_V1", asOf, asOf,
                252, 252, 0,
                new FeaturePreview.LatestCandle(
                        "UPSTOX", close, close, close, close, BigDecimal.TEN),
                values, true, false, "reviewed");
    }
}
