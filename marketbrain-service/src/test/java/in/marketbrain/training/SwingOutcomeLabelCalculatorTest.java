package in.marketbrain.training;

import in.marketbrain.feature.FeatureCandle;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SwingOutcomeLabelCalculatorTest {

    private final SwingOutcomeLabelCalculator calculator = new SwingOutcomeLabelCalculator();

    @Test
    void calculatesSeparatedReturnsExcursionsDrawdownAndCost() {
        LocalDate firstDate = LocalDate.of(2026, 1, 2);
        LocalDate secondDate = LocalDate.of(2026, 1, 5);
        var outcomes = new LinkedHashMap<Integer, LocalDate>();
        outcomes.put(1, firstDate);
        outcomes.put(2, secondDate);
        List<FeatureCandle> candles = List.of(
                candle(firstDate, "100", "110", "90", "105"),
                candle(secondDate, "105", "120", "80", "90")
        );

        List<SwingOutcomeLabel> labels = calculator.calculate(
                new BigDecimal("100"), candles, outcomes, 50);

        assertThat(labels).hasSize(2);
        assertThat(labels.getFirst().grossReturnPercent()).isEqualByComparingTo("5.000000");
        assertThat(labels.getFirst().netReturnPercent()).isEqualByComparingTo("4.500000");
        assertThat(labels.getFirst().maximumFavorableExcursionPercent()).isEqualByComparingTo("10.000000");
        assertThat(labels.getFirst().maximumAdverseExcursionPercent()).isEqualByComparingTo("-10.000000");
        assertThat(labels.getLast().grossReturnPercent()).isEqualByComparingTo("-10.000000");
        assertThat(labels.getLast().maximumFavorableExcursionPercent()).isEqualByComparingTo("20.000000");
        assertThat(labels.getLast().maximumAdverseExcursionPercent()).isEqualByComparingTo("-20.000000");
        assertThat(labels.getLast().maximumDrawdownPercent()).isEqualByComparingTo("14.285714");
    }

    @Test
    void omitsAnOutcomeWhenItsExactMarketSessionCandleIsMissing() {
        LocalDate firstDate = LocalDate.of(2026, 1, 2);
        LocalDate missingDate = LocalDate.of(2026, 1, 5);
        var outcomes = new LinkedHashMap<Integer, LocalDate>();
        outcomes.put(1, firstDate);
        outcomes.put(2, missingDate);

        List<SwingOutcomeLabel> labels = calculator.calculate(
                new BigDecimal("100"),
                List.of(candle(firstDate, "100", "110", "90", "105")),
                outcomes,
                50);

        assertThat(labels).extracting(SwingOutcomeLabel::horizonSessions).containsExactly(1);
    }

    private FeatureCandle candle(
            LocalDate date,
            String open,
            String high,
            String low,
            String close
    ) {
        return new FeatureCandle(
                date, "UPSTOX", new BigDecimal(open), new BigDecimal(high),
                new BigDecimal(low), new BigDecimal(close), BigDecimal.TEN, false);
    }
}
