package in.marketbrain.marketdata.upstox;

import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

class UpstoxDataQualityServiceTest {

    private static final Instant NOW = Instant.parse("2026-09-02T06:00:00Z");
    private final UpstoxDataQualityService service = new UpstoxDataQualityService(
            new MarketBrainProperties("PAPER", null, null,
                    new MarketBrainProperties.Signal(90, 60), null, null, null),
            Clock.fixed(NOW, ZoneOffset.UTC));

    @Test
    void freshQuoteIsActionable() {
        var quote = quoteAt(NOW.minusSeconds(45));

        MarketDataQuality result = service.assess(quote);

        assertThat(result.status()).isEqualTo("FRESH");
        assertThat(result.ageSeconds()).isEqualTo(45);
        assertThat(result.isUsableForAction()).isTrue();
    }

    @Test
    void staleQuoteIsAuditedButBlockedForAction() {
        MarketDataQuality result = service.assess(quoteAt(NOW.minusSeconds(91)));

        assertThat(result.status()).isEqualTo("STALE");
        assertThat(result.isUsableForAction()).isFalse();
    }

    @Test
    void rejectsAnImpossibleOhlcCandle() {
        var candle = new UpstoxCandle(NOW, new BigDecimal("100"), new BigDecimal("99"),
                new BigDecimal("95"), new BigDecimal("101"), BigDecimal.TEN);

        assertThat(service.validCandle(candle)).isFalse();
    }

    private UpstoxQuote quoteAt(Instant timestamp) {
        return new UpstoxQuote("NSE_EQ|INE009A01021", "INFY", new BigDecimal("1500"),
                new BigDecimal("1490"), BigDecimal.TEN, timestamp, timestamp);
    }
}
