package in.marketbrain.whatsapp;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class WhatsAppAlertAuditMigrationTest {

    @Test
    void permitsWhatsappOnlyAsAnExplicitAlertDeliveryChannel() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V21__enable_whatsapp_alert_audit.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("delivery_channel IN ('TELEGRAM', 'WHATSAPP')");
            assertThat(sql).contains("WhatsApp remains sandbox-only");
        }
    }
}
