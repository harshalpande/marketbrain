package in.marketbrain.whatsapp;

import org.junit.jupiter.api.Test;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

import static org.assertj.core.api.Assertions.assertThat;

class WhatsAppSecurityTest {

    @Test
    void verifiesTheExactRawPayloadSignature() throws Exception {
        byte[] payload = "{\"object\":\"whatsapp_business_account\"}"
                .getBytes(StandardCharsets.UTF_8);
        String secret = "local-test-app-secret";
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        String signature = "sha256=" + HexFormat.of().formatHex(mac.doFinal(payload));

        assertThat(WhatsAppSecurity.validSignature(payload, signature, secret)).isTrue();
        assertThat(WhatsAppSecurity.validSignature(
                "altered".getBytes(StandardCharsets.UTF_8), signature, secret)).isFalse();
        assertThat(WhatsAppSecurity.validSignature(payload, "sha256=not-hex", secret)).isFalse();
        assertThat(WhatsAppSecurity.validSignature(payload, null, secret)).isFalse();
    }
}
