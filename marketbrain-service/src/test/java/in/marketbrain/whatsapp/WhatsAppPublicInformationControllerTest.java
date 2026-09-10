package in.marketbrain.whatsapp;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import static org.assertj.core.api.Assertions.assertThat;

class WhatsAppPublicInformationControllerTest {

    private final WhatsAppPublicInformationController controller =
            new WhatsAppPublicInformationController();

    @Test
    void publishesAnAccuratePrivateSandboxPrivacyPolicy() {
        var response = controller.privacyPolicy();

        assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
        assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.TEXT_HTML);
        assertThat(response.getHeaders().getFirst("Content-Security-Policy"))
                .contains("default-src 'none'")
                .contains("frame-ancestors 'none'");
        assertThat(response.getBody())
                .contains("private, single-user")
                .contains("does not retain raw webhook JSON")
                .contains("cannot place broker orders")
                .contains("kkool.harshal+whatsapp@gmail.com")
                .contains("/api/v1/whatsapp/data-deletion");
    }

    @Test
    void publishesManualDataDeletionInstructionsWithoutRequestingSecrets() {
        var response = controller.dataDeletionInstructions();

        assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
        assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.TEXT_HTML);
        assertThat(response.getBody())
                .contains("MarketBrain WhatsApp Data Deletion")
                .contains("within 30 days")
                .contains("Do not include passwords, access tokens, App Secrets")
                .contains("kkool.harshal+whatsapp@gmail.com")
                .contains("/api/v1/whatsapp/privacy");
    }
}
