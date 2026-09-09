package in.marketbrain.training;

import in.marketbrain.feature.FeaturePreview;
import in.marketbrain.feature.FeatureValues;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class SwingTrainingDatasetManifestHasherTest {

    private final SwingTrainingDatasetManifestHasher hasher = new SwingTrainingDatasetManifestHasher();
    private final UUID snapshotId = UUID.fromString("83ec77aa-3a5a-4e03-8fab-5f7088b55cee");
    private final LocalDate asOf = LocalDate.of(2026, 6, 5);
    private final LocalDate labelThrough = LocalDate.of(2026, 9, 8);

    @Test
    void hashIsStableAndChangesWhenAnOutcomeChanges() {
        SwingTrainingCohortItem first = item("5.000000");
        SwingTrainingCohortItem changed = item("6.000000");
        List<SwingBenchmarkOutcome> benchmark = List.of(new SwingBenchmarkOutcome(
                5, LocalDate.of(2026, 6, 12), 1, new BigDecimal("5.000000")));

        String hash = hasher.hash(
                snapshotId, asOf, labelThrough, "a".repeat(64), 50,
                benchmark, List.of(first));

        assertThat(hash).hasSize(64).matches("[0-9a-f]{64}");
        assertThat(hasher.hash(
                snapshotId, asOf, labelThrough, "a".repeat(64), 50,
                benchmark, List.of(first))).isEqualTo(hash);
        assertThat(hasher.hash(
                snapshotId, asOf, labelThrough, "a".repeat(64), 50,
                benchmark, List.of(changed))).isNotEqualTo(hash);
    }

    private SwingTrainingCohortItem item(String grossReturn) {
        BigDecimal close = new BigDecimal("100.000000");
        FeatureValues values = new FeatureValues(
                close, BigDecimal.ONE, close, close, close, close, close,
                BigDecimal.valueOf(50), BigDecimal.ONE, BigDecimal.TEN,
                BigDecimal.ONE, BigDecimal.valueOf(50));
        FeaturePreview feature = new FeaturePreview(
                "ELIGIBLE", "RELIANCE", "TECHNICAL_V1", asOf, asOf,
                252, 252, 0,
                new FeaturePreview.LatestCandle(
                        "UPSTOX", close, close, close, close, BigDecimal.TEN),
                values, true, false, "reviewed");
        SwingOutcomeLabel label = new SwingOutcomeLabel(
                5, LocalDate.of(2026, 6, 12), new BigDecimal(grossReturn),
                new BigDecimal("0.500000"), new BigDecimal("4.500000"),
                BigDecimal.TEN, BigDecimal.ZERO, BigDecimal.ZERO,
                new BigDecimal("5.000000"), BigDecimal.ZERO);
        return new SwingTrainingCohortItem(
                "RELIANCE", "LABELED", feature, List.of(label), List.of(20, 60), "preview");
    }
}
