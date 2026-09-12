package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaGuidedRankingPreviewServiceSourceTest {

    @Test
    void guidedPreviewIsReadOnlyAndHasResponseGuardrails() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaGuidedRankingPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("@Transactional(readOnly = true");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).contains("generateJson");
        assertThat(source).contains("validateResponse");
        assertThat(source).contains("RESPONSE_SCHEMA_VERSION");
        assertThat(source).contains("POSITIVE_WINNER");
        assertThat(source).contains("NEGATIVE_LOSER");
        assertThat(source).contains("FALSE_CONFIDENCE_TRAP");
        assertThat(source).contains("SMOOTH_OUTPERFORMER");
        assertThat(source).contains("RECOVERY_OUTPERFORMER");
        assertThat(source).contains("OVEREXTENDED_MOMENTUM_TRAP");
        assertThat(source).contains("score_cap_hint");
        assertThat(source).contains("feature_prior_score");
        assertThat(source).contains("RECOVERY_CANDIDATE");
        assertThat(source).contains("EXTREME_OVEREXTENSION");
        assertThat(source).contains("HARD_CAP_54");
        assertThat(source).contains("HARD_CAP_69");
        assertThat(source).contains("SOFT_CAP_84");
        assertThat(source).contains("previewCandidates(");
        assertThat(source).contains("OFFSET ?");
    }
}
