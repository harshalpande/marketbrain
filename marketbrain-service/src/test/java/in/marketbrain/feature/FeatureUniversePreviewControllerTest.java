package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class FeatureUniversePreviewControllerTest {

    @Test
    void delegatesAnExplicitUniverseAsOfDate() {
        FeatureUniversePreviewService service = mock(FeatureUniversePreviewService.class);
        FeatureUniversePreviewController controller = new FeatureUniversePreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 9, 8);
        FeatureUniversePreview expected = new FeatureUniversePreview(
                "REVIEW_REQUIRED", "TECHNICAL_V1", asOf, UUID.randomUUID(), asOf,
                500, 500, 0, 0, 0, 500, 1_000, 1_000, 0,
                "a".repeat(64), true, false, List.of(), "reviewed");
        when(service.preview(asOf)).thenReturn(expected);

        assertThat(controller.preview(asOf)).isSameAs(expected);
    }
}
