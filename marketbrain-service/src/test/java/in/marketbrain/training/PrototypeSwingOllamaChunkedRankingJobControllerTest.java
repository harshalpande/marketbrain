package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingOllamaChunkedRankingJobControllerTest {

    @Test
    void delegatesSubmitAndStatusRequests() {
        PrototypeSwingOllamaChunkedRankingJobService service =
                mock(PrototypeSwingOllamaChunkedRankingJobService.class);
        PrototypeSwingOllamaChunkedRankingJobController controller =
                new PrototypeSwingOllamaChunkedRankingJobController(service);
        UUID jobId = UUID.randomUUID();
        PrototypeSwingOllamaChunkedRankingRequest request =
                new PrototypeSwingOllamaChunkedRankingRequest(
                        UUID.randomUUID(), "ibm/granite4.1:8b", 0, 24, 4, 2, 1, 20);
        PrototypeSwingOllamaChunkedRankingJobStatus expected =
                new PrototypeSwingOllamaChunkedRankingJobStatus(
                        jobId, "QUEUED", 0, 0, 0, 0, 0, 0,
                        "ibm/granite4.1:8b", Instant.now(), null, null, null, null,
                        false, 0, 0, false, "queued");
        when(service.submit(request)).thenReturn(expected);
        when(service.status(jobId)).thenReturn(expected);

        assertThat(controller.submit(request)).isSameAs(expected);
        assertThat(controller.status(jobId)).isSameAs(expected);
    }

    @Test
    void returnsNotFoundForUnknownOrExpiredJobId() {
        PrototypeSwingOllamaChunkedRankingJobService service =
                mock(PrototypeSwingOllamaChunkedRankingJobService.class);
        PrototypeSwingOllamaChunkedRankingJobController controller =
                new PrototypeSwingOllamaChunkedRankingJobController(service);
        UUID jobId = UUID.randomUUID();
        when(service.status(jobId)).thenThrow(new IllegalArgumentException("Unknown Ollama ranking jobId."));

        assertThatThrownBy(() -> controller.status(jobId))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        exception -> assertThat(exception.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND));
    }
}
