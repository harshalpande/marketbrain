package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SwingTrainingDatasetPreviewControllerTest {

    @Test
    void delegatesTheExplicitCohortBoundaryAndCost() {
        SwingTrainingDatasetPreviewService service = mock(SwingTrainingDatasetPreviewService.class);
        SwingTrainingDatasetPreviewController controller =
                new SwingTrainingDatasetPreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 6, 5);
        LocalDate labelThrough = LocalDate.of(2026, 9, 8);
        SwingTrainingDatasetPreview expected = mock(SwingTrainingDatasetPreview.class);
        when(service.preview(asOf, labelThrough, 50)).thenReturn(expected);

        assertThat(controller.preview(asOf, labelThrough, 50)).isSameAs(expected);
    }
}
