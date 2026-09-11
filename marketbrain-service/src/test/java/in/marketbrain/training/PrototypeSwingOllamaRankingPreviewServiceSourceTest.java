package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaRankingPreviewServiceSourceTest {

    @Test
    void rankingPreviewIsReadOnlyExceptForTheBoundedOllamaCall() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaRankingPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("@Transactional(readOnly = true");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).contains("ollamaClient.generate");
        assertThat(source).contains("signalsCreated");
        assertThat(source).contains("ordersCreated");
    }
}
