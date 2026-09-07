package in.marketbrain.marketdata.daily;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class DailyEnrichmentNotificationMigrationTest {

    @Test
    void migrationCreatesIdempotentCompletionAndWarningLedger() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V17__create_daily_enrichment_notifications.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("daily_enrichment_notification");
            assertThat(sql).contains("'COMPLETION', 'WARNING'");
            assertThat(sql).contains("UNIQUE (target_date, notice_kind)");
            assertThat(sql).contains("PREDATES_NOTIFICATION_ACTIVATION");
            assertThat(sql).contains("'SUPPRESSED'");
            assertThat(sql).doesNotContain("DELETE FROM market_candle");
            assertThat(sql).doesNotContain("UPDATE market_candle");
        }
    }
}
