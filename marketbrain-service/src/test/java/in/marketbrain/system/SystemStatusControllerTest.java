package in.marketbrain.system;

import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

class SystemStatusControllerTest {

    @Test
    void reportsPaperModeAndSafetyTiming() {
        var properties = new MarketBrainProperties(
                "PAPER",
                new MarketBrainProperties.Paper(new BigDecimal("100000")),
                new MarketBrainProperties.Ollama("http://127.0.0.1:11434"),
                new MarketBrainProperties.Signal(90, 60),
                new MarketBrainProperties.PaytmMoney("https://developer.paytmmoney.com", false, "")
        );

        var status = new SystemStatusController(properties).status();

        assertThat(status)
                .containsEntry("mode", "PAPER")
                .containsEntry("paperStartingCash", new BigDecimal("100000"))
                .containsEntry("signalMaximumDataAgeSeconds", 90)
                .containsEntry("targetAlertSubmissionSeconds", 60);
    }
}
