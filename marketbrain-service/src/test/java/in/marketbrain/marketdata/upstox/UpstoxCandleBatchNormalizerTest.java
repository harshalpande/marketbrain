package in.marketbrain.marketdata.upstox;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class UpstoxCandleBatchNormalizerTest {

    private final UpstoxCandleBatchNormalizer normalizer = new UpstoxCandleBatchNormalizer();

    @Test
    void collapsesIdenticalDailyCandlesAndKeepsTheOriginalProviderTimestamp() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle("2015-12-30T18:30:00Z", "327.85", "335.45", "326.30", "334.15", "3007696");
        UpstoxCandle marketOpen = candle("2015-12-31T03:45:00Z", "327.8500", "335.450", "326.3", "334.150", "3007696.0");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(marketOpen, midnight));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.candles()).hasSize(1);
        assertThat(result.candles().getFirst().candle().openedAt())
                .isEqualTo(Instant.parse("2015-12-30T18:30:00Z"));
        assertThat(result.candles().getFirst().providerOpenedAt())
                .isEqualTo(Instant.parse("2015-12-30T18:30:00Z"));
    }

    @Test
    void blocksDifferentDailyValuesForTheSameTradingDate() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle first = candle("2015-12-30T18:30:00Z", "327.85", "335.45", "326.30", "334.15", "3007696");
        UpstoxCandle second = candle("2015-12-31T03:45:00Z", "327.85", "335.45", "326.30", "334.25", "3007696");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(first, second));

        assertThat(result.hasConflicts()).isTrue();
        assertThat(result.conflictingTradingDates()).containsExactly(LocalDate.of(2015, 12, 31));
    }

    @Test
    void doesNotNormalizeIntradayCandleTimestamps() {
        UpstoxHistoricalRequest request = new UpstoxHistoricalRequest(
                "NSE_EQ|TEST", "minutes", 1,
                LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 1));
        UpstoxCandle candle = candle("2026-09-01T03:45:00Z", "100", "105", "99", "104", "1000");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(candle));

        assertThat(result.candles().getFirst().candle().openedAt()).isEqualTo(candle.openedAt());
        assertThat(result.candles().getFirst().providerOpenedAt()).isEqualTo(candle.openedAt());
    }

    private UpstoxHistoricalRequest dailyRequest() {
        return new UpstoxHistoricalRequest(
                "NSE_EQ|TEST", "days", 1,
                LocalDate.of(2015, 12, 31), LocalDate.of(2015, 12, 31));
    }

    private UpstoxCandle candle(
            String timestamp,
            String open,
            String high,
            String low,
            String close,
            String volume
    ) {
        return new UpstoxCandle(
                Instant.parse(timestamp),
                new BigDecimal(open),
                new BigDecimal(high),
                new BigDecimal(low),
                new BigDecimal(close),
                new BigDecimal(volume)
        );
    }
}
