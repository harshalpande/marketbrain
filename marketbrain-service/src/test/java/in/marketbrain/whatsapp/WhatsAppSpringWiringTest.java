package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;

class WhatsAppSpringWiringTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(WhatsAppProperties.class, WhatsAppSpringWiringTest::properties)
            .withBean(RestClient.Builder.class, RestClient::builder)
            .withBean(WhatsAppCloudClient.class);

    @Test
    void springSelectsTheProductionConstructor() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(WhatsAppCloudClient.class);
        });
    }

    private static WhatsAppProperties properties() {
        return new WhatsAppProperties(
                true, true, true, true, "v26.0", "123456789", "987654321",
                "local-test-token", "local-test-app-secret",
                "0123456789abcdef0123456789abcdef", "919999999999");
    }
}
