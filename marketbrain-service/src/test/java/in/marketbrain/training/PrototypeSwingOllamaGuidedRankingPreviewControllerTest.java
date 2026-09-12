package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingOllamaGuidedRankingPreviewControllerTest {

    @Test
    void delegatesGuidedRankingPreviewRequest() {
        PrototypeSwingOllamaGuidedRankingPreviewService service =
                mock(PrototypeSwingOllamaGuidedRankingPreviewService.class);
        PrototypeSwingOllamaGuidedRankingPreviewController controller =
                new PrototypeSwingOllamaGuidedRankingPreviewController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingOllamaRankingRequest request =
                new PrototypeSwingOllamaRankingRequest(runId, "gemma3:4b", 12, 20);
        PrototypeSwingOllamaGuidedRankingPreview expected = new PrototypeSwingOllamaGuidedRankingPreview(
                "REVIEW_REQUIRED", runId, "PROTOTYPE_SWING_TRAINING_DATASET_V1",
                "CURRENT_SNAPSHOT_PROTOTYPE", LocalDate.of(2026, 6, 5),
                LocalDate.of(2026, 9, 8), "a".repeat(64), "gemma3:4b",
                12, 12, 8, 20, "INSTRUCTION_V1", "SCHEMA_V1", "RUBRIC_V1",
                "b".repeat(64), "c".repeat(64), "d".repeat(64),
                "prompt", "{}", 6, 2, 123L, 456L, 7, 8, List.of(), List.of(), true, true, List.of(),
                true, false, true, true, false, true, true,
                false, 1, 0, 0, false, "review");
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
