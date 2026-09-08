package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class DailyFeatureSnapshotAutomationMigrationTest {

    @Test
    void migrationCreatesDurableAutomationAndFeatureNotificationKinds() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V19__create_daily_feature_snapshot_automation.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("CREATE TABLE daily_feature_snapshot_automation");
            assertThat(sql).contains("UNIQUE (target_date)");
            assertThat(sql).contains("'PENDING', 'RUNNING', 'RETRY', 'COMPLETED'");
            assertThat(sql).contains("'FEATURE_COMPLETION', 'FEATURE_WARNING'");
            assertThat(sql).doesNotContain("DELETE FROM market_candle");
            assertThat(sql).doesNotContain("UPDATE market_candle");
        }
    }
}
