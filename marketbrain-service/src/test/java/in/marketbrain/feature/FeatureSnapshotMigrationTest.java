package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class FeatureSnapshotMigrationTest {

    @Test
    void migrationCreatesImmutableGovernedFeatureSnapshots() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V18__create_governed_feature_snapshots.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("CREATE TABLE feature_snapshot_run");
            assertThat(sql).contains("CREATE TABLE feature_snapshot_item");
            assertThat(sql).contains("uk_feature_snapshot_scope");
            assertThat(sql).contains("ck_feature_snapshot_complete_vector");
            assertThat(sql).contains("reject_feature_snapshot_item_mutation");
            assertThat(sql).contains("BEFORE UPDATE OR DELETE ON feature_snapshot_item");
            assertThat(sql).contains("govern_feature_snapshot_run_mutation");
            assertThat(sql).contains("BEFORE UPDATE OR DELETE ON feature_snapshot_run");
            assertThat(sql).contains("OLD.status = 'COMPLETED'");
            assertThat(sql).contains("classification <> 'ELIGIBLE'");
        }
    }
}
