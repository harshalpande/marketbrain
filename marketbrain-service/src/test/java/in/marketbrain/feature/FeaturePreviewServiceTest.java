package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class FeaturePreviewServiceTest {

    private static final LocalDate REQUESTED = LocalDate.of(2026, 9, 8);

    @Test
    void separatesFeatureComputabilityFromFreshness() {
        assertThat(FeaturePreviewService.classification(3_720, REQUESTED, REQUESTED))
                .isEqualTo("ELIGIBLE");
        assertThat(FeaturePreviewService.classification(3_720, REQUESTED.minusDays(4), REQUESTED))
                .isEqualTo("STALE");
        assertThat(FeaturePreviewService.classification(251, REQUESTED, REQUESTED))
                .isEqualTo("INSUFFICIENT_HISTORY");
        assertThat(FeaturePreviewService.classification(0, null, REQUESTED))
                .isEqualTo("NO_ELIGIBLE_DATA");
    }
}
