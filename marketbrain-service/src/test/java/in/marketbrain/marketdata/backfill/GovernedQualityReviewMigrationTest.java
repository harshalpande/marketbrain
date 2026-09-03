package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class GovernedQualityReviewMigrationTest {

    @Test
    void migrationAddsAppendOnlyEvidenceAndFeatureExclusionsWithoutTouchingCandles() throws IOException {
        String migration = migrationText();

        assertThat(migration).contains("CREATE TABLE corporate_action_event");
        assertThat(migration).contains("CREATE TABLE market_data_quality_resolution_event");
        assertThat(migration).contains("CREATE VIEW current_market_data_quality_resolution");
        assertThat(migration).contains("CREATE VIEW market_data_feature_exclusion");
        assertThat(migration).contains("trg_quality_resolution_append_only");
        assertThat(migration).contains("'PROVIDER_OMISSION_CONFIRMED'");
        assertThat(migration).contains("'CORPORATE_ACTION_TRANSITION'");
        assertThat(migration).doesNotContain("DELETE FROM market_candle");
        assertThat(migration).doesNotContain("UPDATE market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V10__create_governed_market_data_review.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
