package in.marketbrain.marketdata.daily;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class DailyEnrichmentMigrationTest {

    @Test
    void migrationAddsGovernedDailyRuns() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V16__create_daily_enrichment_runs.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("job_type = 'DAILY'");
            assertThat(sql).contains("selection_manifest_hash");
            assertThat(sql).contains("selection_manifest_hash IS NOT NULL");
            assertThat(sql).contains("uk_historical_backfill_daily_target");
            assertThat(sql).contains("^[0-9a-f]{64}$");
        }
    }
}
