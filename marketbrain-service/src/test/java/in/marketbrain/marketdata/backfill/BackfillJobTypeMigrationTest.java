package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class BackfillJobTypeMigrationTest {

    @Test
    void migrationPreservesExistingJobsAsPilotAndUniquelyNumbersExpansionBatches() throws IOException {
        String migration = migrationText();

        assertThat(migration).contains("job_type VARCHAR(24) NOT NULL DEFAULT 'PILOT'");
        assertThat(migration).contains("job_type = 'EXPANSION'");
        assertThat(migration).contains("batch_number > 0");
        assertThat(migration).contains("CREATE UNIQUE INDEX uk_historical_backfill_expansion_batch");
        assertThat(migration).contains("CREATE UNIQUE INDEX uk_historical_backfill_single_active_job");
        assertThat(migration).doesNotContain("DELETE FROM historical_backfill_job");
        assertThat(migration).doesNotContain("UPDATE market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V8__classify_backfill_jobs.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
