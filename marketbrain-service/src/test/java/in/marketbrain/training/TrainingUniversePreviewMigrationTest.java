package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class TrainingUniversePreviewMigrationTest {

    @Test
    void migrationAddsReadOnlyPreviewIndexesWithoutTradingSideEffects() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V24__optimize_training_universe_preview.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("idx_instrument_active_nse_symbol");
            assertThat(sql).contains("idx_market_candle_daily_complete_preview");
            assertThat(sql).contains("WHERE interval_code = 'days:1' AND is_complete = TRUE");
            assertThat(sql).doesNotContain("INSERT INTO market_signal");
            assertThat(sql).doesNotContain("INSERT INTO paper_order");
            assertThat(sql).doesNotContain("INSERT INTO paper_fill");
        }
    }
}
