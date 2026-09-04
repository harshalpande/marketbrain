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
    void collapsesIdenticalDailyCandlesAndKeepsTheExchangeAlignedProviderTimestamp() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle("2015-12-30T18:30:00Z", "327.85", "335.45", "326.30", "334.15", "3007696");
        UpstoxCandle marketOpen = candle("2015-12-31T03:45:00Z", "327.8500", "335.450", "326.3", "334.150", "3007696.0");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(marketOpen, midnight));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.normalizedTradingDates()).containsExactly(LocalDate.of(2015, 12, 31));
        assertThat(result.candles()).hasSize(1);
        assertThat(result.candles().getFirst().candle().openedAt())
                .isEqualTo(Instant.parse("2015-12-30T18:30:00Z"));
        assertThat(result.candles().getFirst().providerOpenedAt())
                .isEqualTo(Instant.parse("2015-12-31T03:45:00Z"));
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
    void mergesAOnePaisaHighOrLowRoundingDifferenceUsingTheWiderRange() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle("2015-12-30T18:30:00Z", "238.27", "239.86", "236.49", "237.59", "8546445");
        UpstoxCandle marketOpen = candle("2015-12-31T03:45:00Z", "238.27", "239.85", "236.50", "237.59", "8546445");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(marketOpen, midnight));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.candles().getFirst().candle().high()).isEqualByComparingTo("239.86");
        assertThat(result.candles().getFirst().candle().low()).isEqualByComparingTo("236.49");
    }

    @Test
    void mergesOnePaisaDifferencesAcrossEveryOhlcFieldUsingTheExchangeAlignedOpenAndClose() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "36.54", "37.50", "36.29", "36.89", "1573101");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "36.55", "37.49", "36.30", "36.90", "1573101");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(midnight, marketOpen));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.normalizedTradingDates()).containsExactly(LocalDate.of(2015, 12, 31));
        assertThat(result.candles()).hasSize(1);
        assertThat(result.candles().getFirst().candle().open()).isEqualByComparingTo("36.55");
        assertThat(result.candles().getFirst().candle().high()).isEqualByComparingTo("37.50");
        assertThat(result.candles().getFirst().candle().low()).isEqualByComparingTo("36.29");
        assertThat(result.candles().getFirst().candle().close()).isEqualByComparingTo("36.90");
        assertThat(result.candles().getFirst().providerOpenedAt())
                .isEqualTo(Instant.parse("2015-12-31T03:45:00Z"));
    }

    @Test
    void blocksAnOpenOrCloseDifferenceGreaterThanOnePaisa() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle first = candle(
                "2015-12-30T18:30:00Z", "36.54", "37.50", "36.29", "36.89", "1573101");
        UpstoxCandle second = candle(
                "2015-12-31T03:45:00Z", "36.56", "37.50", "36.29", "36.91", "1573101");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(first, second));

        assertThat(result.hasConflicts()).isTrue();
    }

    @Test
    void normalizesTheReviewedAlkemTimestampTransitionVolumeVariance() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "1460.0", "1496.6", "1442.5", "1485.25", "774495");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "1460.0", "1496.6", "1442.5", "1485.25", "774426");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(midnight, marketOpen));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.candles()).hasSize(1);
        assertThat(result.candles().getFirst().providerOpenedAt())
                .isEqualTo(Instant.parse("2015-12-31T03:45:00Z"));
        assertThat(result.candles().getFirst().candle().volume()).isEqualByComparingTo("774426");
        assertThat(result.normalizationDetails().getFirst())
                .contains("reason=MIDNIGHT_MARKET_OPEN_VOLUME_VARIANCE")
                .contains("retainedOhlcv=[1460.0,1496.6,1442.5,1485.25,774426]")
                .contains("discardedOhlcv=[1460.0,1496.6,1442.5,1485.25,774495]");
    }

    @Test
    void normalizesOnlyTheExactlyReviewedBemlSplitAdjustmentRoundingPair() {
        UpstoxHistoricalRequest request = bemlDailyRequest(LocalDate.of(2015, 12, 31));
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "640.60", "645.50", "633.00", "640.50", "392016");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "640.60", "645.50", "633.00", "640.60", "392016");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(midnight, marketOpen));

        assertThat(result.hasConflicts()).isFalse();
        assertThat(result.collapsedDuplicates()).isEqualTo(1);
        assertThat(result.candles()).singleElement().satisfies(normalized -> {
            assertThat(normalized.providerOpenedAt()).isEqualTo(Instant.parse("2015-12-31T03:45:00Z"));
            assertThat(normalized.candle().close()).isEqualByComparingTo("640.60");
            assertThat(normalized.candle().volume()).isEqualByComparingTo("392016");
        });
        assertThat(result.normalizationDetails()).singleElement().asString()
                .contains("reason=REVIEWED_SPLIT_ADJUSTMENT_CLOSE_ROUNDING")
                .contains("retainedOhlcv=[640.60,645.50,633.00,640.60,392016]")
                .contains("discardedOhlcv=[640.60,645.50,633.00,640.50,392016]")
                .contains("cm31DEC2015bhav.csv.zip")
                .contains("BEML_29092025163552_RECORDDATESIGNED29092025.pdf")
                .contains("reviewedAdjustment=1:2");
    }

    @Test
    void blocksTheBemlValuesForAnUnreviewedInstrument() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "640.60", "645.50", "633.00", "640.50", "392016");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "640.60", "645.50", "633.00", "640.60", "392016");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksAnUnreviewedVariationOfTheBemlPair() {
        UpstoxHistoricalRequest request = bemlDailyRequest(LocalDate.of(2015, 12, 31));
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "640.60", "645.50", "633.00", "640.40", "392016");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "640.60", "645.50", "633.00", "640.60", "392016");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksTheReviewedBemlValuesOnAnotherDate() {
        UpstoxHistoricalRequest request = bemlDailyRequest(LocalDate.of(2016, 1, 1));
        UpstoxCandle midnight = candle(
                "2015-12-31T18:30:00Z", "640.60", "645.50", "633.00", "640.50", "392016");
        UpstoxCandle marketOpen = candle(
                "2016-01-01T03:45:00Z", "640.60", "645.50", "633.00", "640.60", "392016");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksTimestampTransitionWhenAbsoluteVolumeDifferenceExceedsOneHundred() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "100", "105", "99", "104", "1000000");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "100", "105", "99", "104", "1000101");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksTimestampTransitionWhenRelativeVolumeDifferenceExceedsPointZeroOnePercent() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "100", "105", "99", "104", "1000");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "100", "105", "99", "104", "1001");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksVolumeVarianceOutsideTheKnownMidnightMarketOpenTimestampPair() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "100", "105", "99", "104", "1000000");
        UpstoxCandle tenOClock = candle(
                "2015-12-31T04:30:00Z", "100", "105", "99", "104", "1000001");

        assertThat(normalizer.normalize(request, List.of(midnight, tenOClock)).hasConflicts()).isTrue();
    }

    @Test
    void blocksVolumeVarianceWhenOhlcIsNotExactlyIdentical() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle midnight = candle(
                "2015-12-30T18:30:00Z", "100.00", "105", "99", "104", "1000000");
        UpstoxCandle marketOpen = candle(
                "2015-12-31T03:45:00Z", "100.01", "105", "99", "104", "1000001");

        assertThat(normalizer.normalize(request, List.of(midnight, marketOpen)).hasConflicts()).isTrue();
    }

    @Test
    void blocksHighOrLowDifferencesGreaterThanOnePaisa() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle first = candle("2015-12-30T18:30:00Z", "238.27", "239.86", "236.49", "237.59", "8546445");
        UpstoxCandle second = candle("2015-12-31T03:45:00Z", "238.27", "239.86", "236.51", "237.59", "8546445");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(first, second));

        assertThat(result.hasConflicts()).isTrue();
    }

    @Test
    void blocksAChainOfSmallDifferencesWhoseFullRangeExceedsOnePaisa() {
        UpstoxHistoricalRequest request = dailyRequest();
        UpstoxCandle first = candle("2015-12-30T18:30:00Z", "238.27", "239.86", "236.49", "237.59", "8546445");
        UpstoxCandle second = candle("2015-12-31T03:45:00Z", "238.27", "239.87", "236.49", "237.59", "8546445");
        UpstoxCandle third = candle("2015-12-31T04:45:00Z", "238.27", "239.88", "236.49", "237.59", "8546445");

        UpstoxCandleBatchNormalizer.Result result = normalizer.normalize(request, List.of(first, second, third));

        assertThat(result.hasConflicts()).isTrue();
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

    private UpstoxHistoricalRequest bemlDailyRequest(LocalDate tradingDate) {
        return new UpstoxHistoricalRequest(
                "NSE_EQ|INE258A01024", "days", 1, tradingDate, tradingDate);
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
