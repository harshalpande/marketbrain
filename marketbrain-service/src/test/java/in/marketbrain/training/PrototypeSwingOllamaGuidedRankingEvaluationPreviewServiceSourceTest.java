package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaGuidedRankingEvaluationPreviewServiceSourceTest {

    @Test
    void evaluationPreviewIsReadOnlyAndPreservesTradingSafety() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaGuidedRankingEvaluationPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("@Transactional(readOnly = true");
        assertThat(source).contains("public PrototypeSwingOllamaGuidedRankingEvaluationPreviewService(");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).doesNotContain("paper_fill");
        assertThat(source).contains("guided.ollamaCallCount()");
        assertThat(source).contains("false,");
        assertThat(source).contains("0,");
        assertThat(source).contains("HIGH_CONFIDENCE_MISS");
        assertThat(source).contains("NEGATIVE_RANK_CORRELATION");
    }
}
