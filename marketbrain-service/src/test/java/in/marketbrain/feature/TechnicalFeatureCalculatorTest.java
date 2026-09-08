package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.data.Offset.offset;

class TechnicalFeatureCalculatorTest {

    private final TechnicalFeatureCalculator calculator = new TechnicalFeatureCalculator();

    @Test
    void computesDeterministicFeaturesFromAnAscendingPointInTimeSeries() {
        List<FeatureCandle> candles = new ArrayList<>();
        LocalDate firstDate = LocalDate.of(2025, 1, 1);
        for (int index = 0; index < 252; index++) {
            BigDecimal close = BigDecimal.valueOf(100 + index);
            candles.add(candle(firstDate.plusDays(index), close, BigDecimal.valueOf(1_000 + index)));
        }

        FeatureValues features = calculator.calculate(candles);

        assertThat(features.previousClose()).isEqualByComparingTo("350.000000");
        assertThat(features.dailyReturnPercent().doubleValue()).isCloseTo(0.285714, offset(0.000001));
        assertThat(features.sma20()).isEqualByComparingTo("341.500000");
        assertThat(features.sma50()).isEqualByComparingTo("326.500000");
        assertThat(features.sma200()).isEqualByComparingTo("251.500000");
        assertThat(features.rsi14()).isEqualByComparingTo("100.000000");
        assertThat(features.atr14()).isEqualByComparingTo("2.000000");
        assertThat(features.rangePosition252Percent()).isEqualByComparingTo("100.000000");
        assertThat(features.volumeRatio20().doubleValue()).isCloseTo(
                1_251.0 / 1_240.5, offset(0.000001));
        assertThat(features.annualizedVolatility20Percent()).isPositive();
    }

    @Test
    void returnsNeutralMomentumAndRangeForAFlatSeries() {
        List<FeatureCandle> candles = new ArrayList<>();
        LocalDate firstDate = LocalDate.of(2025, 1, 1);
        for (int index = 0; index < 252; index++) {
            candles.add(candle(firstDate.plusDays(index), BigDecimal.valueOf(100), BigDecimal.TEN));
        }

        FeatureValues features = calculator.calculate(candles);

        assertThat(features.rsi14()).isEqualByComparingTo("50.000000");
        assertThat(features.annualizedVolatility20Percent()).isEqualByComparingTo("0.000000");
        assertThat(features.rangePosition252Percent()).isEqualByComparingTo("50.000000");
        assertThat(features.volumeRatio20()).isEqualByComparingTo("1.000000");
    }

    @Test
    void refusesToProduceAPartialFeatureVector() {
        List<FeatureCandle> candles = List.of(
                candle(LocalDate.of(2026, 9, 8), BigDecimal.TEN, BigDecimal.ONE));

        assertThatThrownBy(() -> calculator.calculate(candles))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("252");
    }

    @Test
    void rejectsAnUnorderedSeriesBeforeCalculatingFeatures() {
        List<FeatureCandle> candles = new ArrayList<>();
        LocalDate firstDate = LocalDate.of(2025, 1, 1);
        for (int index = 0; index < 252; index++) {
            candles.add(candle(firstDate.plusDays(index), BigDecimal.TEN, BigDecimal.ONE));
        }
        candles.set(251, candle(firstDate, BigDecimal.TEN, BigDecimal.ONE));

        assertThatThrownBy(() -> calculator.calculate(candles))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("strictly ordered");
    }

    private FeatureCandle candle(LocalDate date, BigDecimal close, BigDecimal volume) {
        return new FeatureCandle(
                date,
                "UPSTOX",
                close.subtract(BigDecimal.ONE),
                close.add(BigDecimal.ONE),
                close.subtract(BigDecimal.ONE),
                close,
                volume,
                false
        );
    }
}
