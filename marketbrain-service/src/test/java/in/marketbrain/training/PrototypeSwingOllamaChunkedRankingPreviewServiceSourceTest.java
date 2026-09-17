package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaChunkedRankingPreviewServiceSourceTest {

    @Test
    void chunkedRankingPreviewIsReadOnlyRetryableAndBounded() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaChunkedRankingPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).doesNotContain("@Transactional");
        assertThat(source).contains("public PrototypeSwingOllamaChunkedRankingPreviewService(");
        assertThat(source).contains("DEFAULT_CHUNK_SIZE = 4");
        assertThat(source).contains("DEFAULT_MAX_RETRIES_PER_CHUNK = 1");
        assertThat(source).contains("maxRetriesPerChunk + 1");
        assertThat(source).contains("boolean lastAttempt = attemptNumber == maxRetriesPerChunk + 1");
        assertThat(source).contains("SCORE_CALIBRATION_WEAK");
        assertThat(source).contains("QUALITY_REVIEW_WEAK");
        assertThat(source).contains("Apply the score_cap_hint rules");
        assertThat(source).contains("SCORE_CAP_VIOLATION");
        assertThat(source).contains("TOP_PICK_GUARD_VIOLATION");
        assertThat(source).contains("Honor score_cap_hint exactly");
        assertThat(source).contains("Exact score cap repairs required");
        assertThat(source).contains("ACCEPTED_BEST_VALID_ATTEMPT_AFTER_RETRY");
        assertThat(source).contains("fallbackEligible");
        assertThat(source).contains("fallbackScore");
        assertThat(source).contains("markAcceptedAttempt");
        assertThat(source).contains("Do not rank a top_pick_eligibility=BLOCKED candidate as rank 1");
        assertThat(source).contains("responseNormalizationWarnings");
        assertThat(source).contains("startOffset(");
        assertThat(source).contains("guidedRankingService.candidates(runId, offset, requestedChunkSize, selectionMode)");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).doesNotContain("paper_fill");
    }
}
