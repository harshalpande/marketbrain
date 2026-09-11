package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingOllamaScoreCalibrationPreviewControllerTest {

    @Test
    void delegatesScoreCalibrationPreviewRequest() {
        PrototypeSwingOllamaScoreCalibrationPreviewService service =
                mock(PrototypeSwingOllamaScoreCalibrationPreviewService.class);
        PrototypeSwingOllamaScoreCalibrationPreviewController controller =
                new PrototypeSwingOllamaScoreCalibrationPreviewController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingOllamaScoreCalibrationRequest request =
                new PrototypeSwingOllamaScoreCalibrationRequest(runId, "gemma3:4b", List.of(5), 20);
        PrototypeSwingOllamaScoreCalibrationPreview expected =
                new PrototypeSwingOllamaScoreCalibrationPreview(
                        "REVIEW_REQUIRED", runId, "gemma3:4b",
                        LocalDate.of(2026, 6, 5), LocalDate.of(2026, 9, 8),
                        20, "CALIBRATION_V1", List.of(5), 1, 1, 1, 0, 0,
                        1, List.of(), List.of(), false, 0, 0, false, "review");
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
