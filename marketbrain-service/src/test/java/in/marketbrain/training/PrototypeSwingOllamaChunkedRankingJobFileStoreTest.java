package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaChunkedRankingJobFileStoreTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void persistsStatusAttemptPromptAndResponseEvidence() throws Exception {
        ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
        PrototypeSwingOllamaChunkedRankingJobFileStore store =
                new PrototypeSwingOllamaChunkedRankingJobFileStore(objectMapper, temporaryDirectory.toString());
        UUID jobId = UUID.randomUUID();
        PrototypeSwingOllamaChunkedRankingJobStatus status =
                new PrototypeSwingOllamaChunkedRankingJobStatus(
                        jobId, "RUNNING", 33, 2, 6, 2, 1, 0,
                        "ibm/granite4.1:8b", Instant.now(), Instant.now(), null,
                        null, null, false, 0, 0, false,
                        "chunk 2", store.jobDirectory(jobId));
        PrototypeSwingOllamaChunkedRankingAttempt attempt =
                new PrototypeSwingOllamaChunkedRankingAttempt(
                        2, 1, null, List.of("CANDIDATE_001"), List.of("ABC"),
                        "prompt-hash", "prompt text", 11,
                        "response-hash", 17, 1234L, 5678L, 90, 12,
                        "{\"rankedCandidates\":[]}", true, false,
                        "SCHEMA_GUARDRAIL_BLOCKED", "SCORE_CALIBRATION_BLOCKED",
                        List.of("RANKED_CANDIDATE_COUNT"), List.of("ENUM_NORMALIZED:reasonCode:X->Y"), List.of(), List.of(),
                        false);

        store.writeStatus(status);
        store.writeAttempt(jobId, attempt);

        PrototypeSwingOllamaChunkedRankingJobStatus recovered = store.readStatus(jobId);
        Path jobDirectory = Path.of(store.jobDirectory(jobId));

        assertThat(recovered.status()).isEqualTo("RUNNING");
        assertThat(Files.readString(jobDirectory.resolve("attempts/chunk-002-attempt-01-prompt.txt")))
                .isEqualTo("prompt text");
        assertThat(Files.readString(jobDirectory.resolve("attempts/chunk-002-attempt-01-ollama-response.json")))
                .isEqualTo("{\"rankedCandidates\":[]}");
        assertThat(jobDirectory.resolve("attempts/chunk-002-attempt-01-attempt.json"))
                .isRegularFile();
    }
}
