package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

class UpstoxSpringWiringTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(MarketBrainProperties.class, UpstoxSpringWiringTest::properties)
            .withBean(ObjectMapper.class, ObjectMapper::new)
            .withBean(RestClient.Builder.class, RestClient::builder)
            .withBean(UpstoxResponseParser.class)
            .withBean(UpstoxReadOnlyClient.class)
            .withBean(UpstoxDataQualityService.class);

    @Test
    void springSelectsTheProductionConstructors() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(UpstoxReadOnlyClient.class);
            assertThat(context).hasSingleBean(UpstoxDataQualityService.class);
        });
    }

    private static MarketBrainProperties properties() {
        return new MarketBrainProperties(
                "PAPER",
                new MarketBrainProperties.Paper(new BigDecimal("100000")),
                new MarketBrainProperties.Ollama("http://127.0.0.1:11434"),
                new MarketBrainProperties.Signal(90, 60),
                new MarketBrainProperties.PaytmMoney("https://developer.paytmmoney.com", false, ""),
                new MarketBrainProperties.Upstox(
                        "https://api.upstox.com",
                        "https://assets.upstox.com/market-quote/instruments/exchange/NSE.json.gz",
                        false,
                        ""),
                new MarketBrainProperties.Telegram(false, "", "", 20, 1000, false)
        );
    }
}
