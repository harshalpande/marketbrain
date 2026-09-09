package in.marketbrain.whatsapp;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class WhatsAppWebhookMigrationTest {

    @Test
    void migrationCreatesAnImmutableContentFreeIdempotencyLedger() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V20__create_whatsapp_webhook_ledger.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("CREATE TABLE whatsapp_webhook_event");
            assertThat(sql).contains("event_key_hash CHAR(64) NOT NULL UNIQUE");
            assertThat(sql).doesNotContain("payload JSON");
            assertThat(sql).contains("reject_whatsapp_webhook_event_mutation");
            assertThat(sql).contains("BEFORE UPDATE OR DELETE ON whatsapp_webhook_event");
        }
    }
}
