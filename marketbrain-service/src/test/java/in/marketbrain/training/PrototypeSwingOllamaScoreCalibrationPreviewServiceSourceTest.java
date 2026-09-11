package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaScoreCalibrationPreviewServiceSourceTest {

    @Test
    void scoreCalibrationPreviewIsReadOnlyAndSafetyBounded() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaScoreCalibrationPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("@Transactional(readOnly = true");
        assertThat(source).contains("public PrototypeSwingOllamaScoreCalibrationPreviewService(");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).doesNotContain("paper_fill");
        assertThat(source).contains("SCORE_SCALE_UNDERUSED");
        assertThat(source).contains("SCORE_SPREAD_TOO_COMPRESSED");
        assertThat(source).contains("NEGATIVE_SCORE_RANK_CORRELATION");
        assertThat(source).contains("At most five candidate limits");
    }
}
