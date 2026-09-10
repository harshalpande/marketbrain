package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WhatsAppWebhookControllerTest {

    private static final String APP_SECRET = "local-test-app-secret";
    private static final String VERIFY_TOKEN = "0123456789abcdef0123456789abcdef";

    @Test
    void returnsTheChallengeOnlyForTheConfiguredVerificationToken() {
        WhatsAppWebhookService service = mock(WhatsAppWebhookService.class);
        WhatsAppWebhookController controller = new WhatsAppWebhookController(properties(), service);

        var accepted = controller.verify("subscribe", VERIFY_TOKEN, "challenge-123");
        var rejected = controller.verify("subscribe", "wrong-token", "challenge-123");

        assertThat(accepted.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(accepted.getBody()).isEqualTo("challenge-123");
        assertThat(rejected.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void rejectsAnUnsignedPayloadWithoutParsingOrPersistingIt() throws Exception {
        WhatsAppWebhookService service = mock(WhatsAppWebhookService.class);
        WhatsAppWebhookController controller = new WhatsAppWebhookController(properties(), service);
        byte[] payload = "{}".getBytes(StandardCharsets.UTF_8);

        var response = controller.receive(payload, "sha256=00");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        verify(service, never()).receive(payload);
    }

    @Test
    void acknowledgesAValidSignedPayloadWithoutExecutingAnAction() throws Exception {
        WhatsAppWebhookService service = mock(WhatsAppWebhookService.class);
        WhatsAppWebhookController controller = new WhatsAppWebhookController(properties(), service);
        byte[] payload = "{}".getBytes(StandardCharsets.UTF_8);
        when(service.receive(payload)).thenReturn(new WhatsAppWebhookResult(1, 0, 0));

        var response = controller.receive(payload, signature(payload));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo("EVENT_RECEIVED");
        verify(service).receive(payload);
    }

    private WhatsAppProperties properties() {
        return new WhatsAppProperties(
                true,
                true,
                true,
                true,
                "v5.0",
                "phone-number-id",
                "waba-id",
                "temporary-test-token",
                APP_SECRET,
                VERIFY_TOKEN,
                "919999999999");
    }

    private String signature(byte[] payload) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(APP_SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return "sha256=" + HexFormat.of().formatHex(mac.doFinal(payload));
    }
}
