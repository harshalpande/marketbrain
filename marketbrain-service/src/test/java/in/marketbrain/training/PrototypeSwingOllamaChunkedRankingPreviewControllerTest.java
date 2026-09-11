package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingOllamaChunkedRankingPreviewControllerTest {

    @Test
    void delegatesChunkedRankingPreviewRequest() {
        PrototypeSwingOllamaChunkedRankingPreviewService service =
                mock(PrototypeSwingOllamaChunkedRankingPreviewService.class);
        PrototypeSwingOllamaChunkedRankingPreviewController controller =
                new PrototypeSwingOllamaChunkedRankingPreviewController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingOllamaChunkedRankingRequest request =
                new PrototypeSwingOllamaChunkedRankingRequest(runId, "gemma3:4b", 0, 12, 4, 2, 1, 20);
        PrototypeSwingOllamaChunkedRankingPreview expected =
                new PrototypeSwingOllamaChunkedRankingPreview(
                        "REVIEW_REQUIRED", runId, "gemma3:4b",
                        LocalDate.of(2026, 6, 5), LocalDate.of(2026, 9, 8),
                        0, 12, 4, 2, 1, 20, "CHUNKED_V1",
                        3, 3, 0, 0, 12, 6, 3,
                        List.of(), List.of(), List.of(), false, 0, 0, false, "review");
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
