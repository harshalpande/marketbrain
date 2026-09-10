package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class TradableEquityTrainingUniverseManifestHasherTest {

    @Test
    void producesStableHashFromCanonicalUniverseFields() {
        var hasher = new TradableEquityTrainingUniverseManifestHasher();
        var item = new TradableEquityTrainingUniverseItem(
                1L, "ABC", "INE000000001", "ABC Limited", "ELIGIBLE",
                LocalDate.of(2011, 1, 3), LocalDate.of(2026, 9, 8),
                3_800, 3_799, 1, "NSE_BHAVCOPY", "eligible");

        String first = hasher.hash(
                TradableEquityTrainingUniversePreviewService.CONTRACT_VERSION,
                LocalDate.of(2026, 9, 8), 252, List.of(item));
        String second = hasher.hash(
                TradableEquityTrainingUniversePreviewService.CONTRACT_VERSION,
                LocalDate.of(2026, 9, 8), 252, List.of(item));

        assertThat(first).isEqualTo(second);
        assertThat(first).matches("[0-9a-f]{64}");
    }
}
