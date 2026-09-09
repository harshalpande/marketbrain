package in.marketbrain.training;

import in.marketbrain.feature.FeatureCandle;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Component
class SwingOutcomeLabelCalculator {

    private static final int SCALE = 6;

    List<SwingOutcomeLabel> calculate(
            BigDecimal referenceClose,
            List<FeatureCandle> futureCandles,
            Map<Integer, LocalDate> outcomeDates,
            int assumedRoundTripCostBps
    ) {
        if (referenceClose == null || referenceClose.signum() <= 0) {
            throw new IllegalArgumentException("A positive reference close is required.");
        }
        validateFutureCandles(futureCandles);
        BigDecimal assumedCostPercent = BigDecimal.valueOf(assumedRoundTripCostBps)
                .divide(BigDecimal.valueOf(100), SCALE, RoundingMode.HALF_UP);
        List<SwingOutcomeLabel> labels = new ArrayList<>();
        for (Map.Entry<Integer, LocalDate> horizon : outcomeDates.entrySet()) {
            FeatureCandle outcome = futureCandles.stream()
                    .filter(candle -> candle.tradingDate().equals(horizon.getValue()))
                    .findFirst()
                    .orElse(null);
            if (outcome == null) {
                continue;
            }
            List<FeatureCandle> path = futureCandles.stream()
                    .filter(candle -> !candle.tradingDate().isAfter(horizon.getValue()))
                    .toList();
            BigDecimal grossReturn = percentChange(outcome.close(), referenceClose);
            BigDecimal favorable = path.stream()
                    .map(FeatureCandle::high)
                    .map(high -> percentChange(high, referenceClose))
                    .max(BigDecimal::compareTo)
                    .orElse(BigDecimal.ZERO)
                    .max(BigDecimal.ZERO);
            BigDecimal adverse = path.stream()
                    .map(FeatureCandle::low)
                    .map(low -> percentChange(low, referenceClose))
                    .min(BigDecimal::compareTo)
                    .orElse(BigDecimal.ZERO)
                    .min(BigDecimal.ZERO);
            BigDecimal maximumDrawdown = maximumDrawdown(referenceClose, path);
            labels.add(new SwingOutcomeLabel(
                    horizon.getKey(),
                    horizon.getValue(),
                    grossReturn,
                    assumedCostPercent,
                    grossReturn.subtract(assumedCostPercent),
                    favorable,
                    adverse,
                    maximumDrawdown,
                    null,
                    null
            ));
        }
        return List.copyOf(labels);
    }

    private void validateFutureCandles(List<FeatureCandle> candles) {
        LocalDate previous = null;
        for (FeatureCandle candle : candles) {
            if (candle.tradingDate() == null || candle.open() == null || candle.high() == null
                    || candle.low() == null || candle.close() == null
                    || candle.open().signum() <= 0 || candle.high().signum() <= 0
                    || candle.low().signum() <= 0 || candle.close().signum() <= 0
                    || candle.low().compareTo(candle.open()) > 0
                    || candle.low().compareTo(candle.close()) > 0
                    || candle.high().compareTo(candle.open()) < 0
                    || candle.high().compareTo(candle.close()) < 0
                    || candle.excluded()) {
                throw new IllegalArgumentException("A future label candle is invalid or excluded.");
            }
            if (previous != null && !candle.tradingDate().isAfter(previous)) {
                throw new IllegalArgumentException("Future label candles must be strictly ordered.");
            }
            previous = candle.tradingDate();
        }
    }

    private BigDecimal maximumDrawdown(BigDecimal referenceClose, List<FeatureCandle> path) {
        BigDecimal runningPeak = referenceClose;
        BigDecimal mostNegative = BigDecimal.ZERO;
        for (FeatureCandle candle : path) {
            runningPeak = runningPeak.max(candle.close());
            mostNegative = mostNegative.min(percentChange(candle.close(), runningPeak));
        }
        return mostNegative.abs();
    }

    private BigDecimal percentChange(BigDecimal value, BigDecimal reference) {
        return value.divide(reference, 12, RoundingMode.HALF_UP)
                .subtract(BigDecimal.ONE)
                .multiply(BigDecimal.valueOf(100))
                .setScale(SCALE, RoundingMode.HALF_UP);
    }
}
