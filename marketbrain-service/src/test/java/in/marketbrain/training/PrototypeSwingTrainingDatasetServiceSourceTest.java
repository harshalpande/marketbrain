package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingTrainingDatasetServiceSourceTest {

    @Test
    void itemPersistenceRequestsOnlyTheGeneratedItemId() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingTrainingDatasetService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("new String[]{\"id\"}");
        assertThat(source).doesNotContain("Statement.RETURN_GENERATED_KEYS");
        assertThat(source).contains("persistence progress");
    }
}
