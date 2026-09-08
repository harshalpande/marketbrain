package in.marketbrain.feature;

import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class FeaturePreviewControllerTest {

    @Test
    void delegatesAnExplicitPointInTimeRequest() {
        FeaturePreviewService service = mock(FeaturePreviewService.class);
        FeaturePreviewController controller = new FeaturePreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 9, 8);
        FeaturePreview expected = new FeaturePreview(
                "ELIGIBLE", "RELIANCE", "TECHNICAL_V1", asOf, asOf, 252, 252, 0,
                null, null, true, false, "reviewed");
        when(service.preview("RELIANCE", asOf)).thenReturn(expected);

        assertThat(controller.preview("RELIANCE", asOf)).isSameAs(expected);
    }

    @Test
    void mapsAnInvalidSymbolToBadRequest() {
        FeaturePreviewService service = mock(FeaturePreviewService.class);
        FeaturePreviewController controller = new FeaturePreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 9, 8);
        when(service.preview("UNKNOWN", asOf)).thenThrow(new IllegalArgumentException("not found"));

        assertThatThrownBy(() -> controller.preview("UNKNOWN", asOf))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("400 BAD_REQUEST");
    }
}
