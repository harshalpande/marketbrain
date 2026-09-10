package in.marketbrain.notification;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class DualNotificationMigrationTest {

    @Test
    void migrationCreatesPerChannelDeduplicationWithoutChangingTradingData() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V22__create_idempotent_dual_notification_delivery.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("delivery_deduplication_key");
            assertThat(sql).contains("UNIQUE (delivery_channel, delivery_deduplication_key)");
            assertThat(sql).doesNotContain("market_candle");
            assertThat(sql).doesNotContain("market_signal");
            assertThat(sql).doesNotContain("paper_order");
        }
    }
}
