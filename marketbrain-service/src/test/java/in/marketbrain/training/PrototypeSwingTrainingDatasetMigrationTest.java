package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingTrainingDatasetMigrationTest {

    @Test
    void migrationCreatesImmutablePrototypeDatasetWithoutTradingSideEffects() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V25__create_prototype_swing_training_dataset.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("CREATE TABLE prototype_swing_training_dataset_run");
            assertThat(sql).contains("CREATE TABLE prototype_swing_training_dataset_item");
            assertThat(sql).contains("CREATE TABLE prototype_swing_training_dataset_label");
            assertThat(sql).contains("PROTOTYPE_SWING_TRAINING_DATASET_V1");
            assertThat(sql).contains("CURRENT_SNAPSHOT_PROTOTYPE");
            assertThat(sql).contains("benchmark_training_eligible = FALSE");
            assertThat(sql).contains("reject_prototype_swing_training_dataset_mutation");
            assertThat(sql).doesNotContain("INSERT INTO market_signal");
            assertThat(sql).doesNotContain("INSERT INTO paper_order");
            assertThat(sql).doesNotContain("INSERT INTO paper_fill");
        }
    }
}
