package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingOllamaRankingPreviewControllerTest {

    @Test
    void delegatesRankingPreviewRequest() {
        PrototypeSwingOllamaRankingPreviewService service = mock(PrototypeSwingOllamaRankingPreviewService.class);
        PrototypeSwingOllamaRankingPreviewController controller =
                new PrototypeSwingOllamaRankingPreviewController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingOllamaRankingRequest request =
                new PrototypeSwingOllamaRankingRequest(runId, "llama3.1:8b", 12, 20);
        PrototypeSwingOllamaRankingPreview expected = new PrototypeSwingOllamaRankingPreview(
                "REVIEW_REQUIRED", runId, "PROTOTYPE_SWING_TRAINING_DATASET_V1",
                "CURRENT_SNAPSHOT_PROTOTYPE", LocalDate.of(2026, 6, 5),
                LocalDate.of(2026, 9, 8), "a".repeat(64), "llama3.1:8b",
                12, 12, 20, "b".repeat(64), "c".repeat(64),
                "prompt", "response", List.of(), true, true, false,
                true, true, false, 1, 0, 0, false, "review");
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
