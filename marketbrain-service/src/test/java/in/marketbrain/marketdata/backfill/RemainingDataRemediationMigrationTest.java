package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class RemainingDataRemediationMigrationTest {

    @Test
    void migrationAddsASeparateOfficialSourceAndResumableCheckpointsWithoutRewritingCandles() throws IOException {
        String migration = migrationText();

        assertThat(migration).contains("'NSE_BHAVCOPY'");
        assertThat(migration).contains("CREATE TABLE remaining_data_remediation_plan");
        assertThat(migration).contains("CREATE TABLE remaining_data_remediation_item");
        assertThat(migration).contains("secondary_candle_ready");
        assertThat(migration).contains("resolution_event_id");
        assertThat(migration).doesNotContain("UPDATE market_candle");
        assertThat(migration).doesNotContain("DELETE FROM market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V12__create_remaining_data_remediation.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
