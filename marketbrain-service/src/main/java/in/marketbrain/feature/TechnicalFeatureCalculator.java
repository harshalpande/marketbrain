package in.marketbrain.feature;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

@Component
public class TechnicalFeatureCalculator {

    private static final int SCALE = 6;
    private static final double TRADING_DAYS_PER_YEAR = 252.0;

    public FeatureValues calculate(List<FeatureCandle> candles) {
        if (candles.size() < 252) {
            throw new IllegalArgumentException("At least 252 eligible daily observations are required.");
        }
        validate(candles);

        int last = candles.size() - 1;
        double latestClose = close(candles.get(last));
        double previousClose = close(candles.get(last - 1));
        return new FeatureValues(
                decimal(previousClose),
                decimal(percentChange(latestClose, previousClose)),
                decimal(simpleMovingAverage(candles, 20)),
                decimal(simpleMovingAverage(candles, 50)),
                decimal(simpleMovingAverage(candles, 200)),
                decimal(exponentialMovingAverage(candles, 12)),
                decimal(exponentialMovingAverage(candles, 26)),
                decimal(relativeStrengthIndex(candles, 14)),
                decimal(averageTrueRange(candles, 14)),
                decimal(annualizedVolatility(candles, 20)),
                nullableDecimal(volumeRatio(candles, 20)),
                decimal(rangePosition(candles, 252))
        );
    }

    private void validate(List<FeatureCandle> candles) {
        for (int index = 0; index < candles.size(); index++) {
            FeatureCandle candle = candles.get(index);
            if (candle.tradingDate() == null || candle.open() == null || candle.high() == null
                    || candle.low() == null || candle.close() == null
                    || candle.open().signum() <= 0 || candle.high().signum() <= 0
                    || candle.low().signum() <= 0 || candle.close().signum() <= 0
                    || candle.low().compareTo(candle.open()) > 0
                    || candle.low().compareTo(candle.close()) > 0
                    || candle.high().compareTo(candle.open()) < 0
                    || candle.high().compareTo(candle.close()) < 0
                    || (candle.volume() != null && candle.volume().signum() < 0)) {
                throw new IllegalArgumentException("The feature input contains an invalid daily candle.");
            }
            if (index > 0 && !candle.tradingDate().isAfter(candles.get(index - 1).tradingDate())) {
                throw new IllegalArgumentException("Feature candles must be strictly ordered by trading date.");
            }
        }
    }

    private double simpleMovingAverage(List<FeatureCandle> candles, int period) {
        return candles.subList(candles.size() - period, candles.size()).stream()
                .mapToDouble(this::close)
                .average()
                .orElseThrow();
    }

    private double exponentialMovingAverage(List<FeatureCandle> candles, int period) {
        double multiplier = 2.0 / (period + 1.0);
        double ema = close(candles.getFirst());
        for (int index = 1; index < candles.size(); index++) {
            ema = close(candles.get(index)) * multiplier + ema * (1.0 - multiplier);
        }
        return ema;
    }

    private double relativeStrengthIndex(List<FeatureCandle> candles, int period) {
        double gain = 0.0;
        double loss = 0.0;
        for (int index = 1; index <= period; index++) {
            double change = close(candles.get(index)) - close(candles.get(index - 1));
            gain += Math.max(change, 0.0);
            loss += Math.max(-change, 0.0);
        }
        double averageGain = gain / period;
        double averageLoss = loss / period;
        for (int index = period + 1; index < candles.size(); index++) {
            double change = close(candles.get(index)) - close(candles.get(index - 1));
            averageGain = ((averageGain * (period - 1)) + Math.max(change, 0.0)) / period;
            averageLoss = ((averageLoss * (period - 1)) + Math.max(-change, 0.0)) / period;
        }
        if (averageGain == 0.0 && averageLoss == 0.0) {
            return 50.0;
        }
        if (averageLoss == 0.0) {
            return 100.0;
        }
        return 100.0 - (100.0 / (1.0 + averageGain / averageLoss));
    }

    private double averageTrueRange(List<FeatureCandle> candles, int period) {
        double atr = 0.0;
        for (int index = 0; index < period; index++) {
            atr += trueRange(candles, index);
        }
        atr /= period;
        for (int index = period; index < candles.size(); index++) {
            atr = ((atr * (period - 1)) + trueRange(candles, index)) / period;
        }
        return atr;
    }

    private double trueRange(List<FeatureCandle> candles, int index) {
        FeatureCandle candle = candles.get(index);
        double highLow = candle.high().doubleValue() - candle.low().doubleValue();
        if (index == 0) {
            return highLow;
        }
        double priorClose = close(candles.get(index - 1));
        return Math.max(highLow, Math.max(
                Math.abs(candle.high().doubleValue() - priorClose),
                Math.abs(candle.low().doubleValue() - priorClose)));
    }

    private double annualizedVolatility(List<FeatureCandle> candles, int period) {
        int firstReturnIndex = candles.size() - period;
        double[] returns = new double[period];
        double mean = 0.0;
        for (int offset = 0; offset < period; offset++) {
            int index = firstReturnIndex + offset;
            returns[offset] = Math.log(close(candles.get(index)) / close(candles.get(index - 1)));
            mean += returns[offset];
        }
        mean /= period;
        double sumSquaredDeviation = 0.0;
        for (double value : returns) {
            sumSquaredDeviation += Math.pow(value - mean, 2.0);
        }
        double sampleDeviation = Math.sqrt(sumSquaredDeviation / (period - 1));
        return sampleDeviation * Math.sqrt(TRADING_DAYS_PER_YEAR) * 100.0;
    }

    private Double volumeRatio(List<FeatureCandle> candles, int period) {
        int last = candles.size() - 1;
        if (candles.get(last).volume() == null) {
            return null;
        }
        double total = 0.0;
        for (int index = last - period; index < last; index++) {
            if (candles.get(index).volume() == null) {
                return null;
            }
            total += candles.get(index).volume().doubleValue();
        }
        double average = total / period;
        return average == 0.0 ? null : candles.get(last).volume().doubleValue() / average;
    }

    private double rangePosition(List<FeatureCandle> candles, int period) {
        List<FeatureCandle> window = candles.subList(candles.size() - period, candles.size());
        double minimum = window.stream().mapToDouble(this::close).min().orElseThrow();
        double maximum = window.stream().mapToDouble(this::close).max().orElseThrow();
        if (maximum == minimum) {
            return 50.0;
        }
        return ((close(candles.getLast()) - minimum) / (maximum - minimum)) * 100.0;
    }

    private double percentChange(double current, double previous) {
        return ((current / previous) - 1.0) * 100.0;
    }

    private double close(FeatureCandle candle) {
        return candle.close().doubleValue();
    }

    private BigDecimal decimal(double value) {
        if (!Double.isFinite(value)) {
            throw new IllegalArgumentException("A feature calculation produced a non-finite value.");
        }
        return BigDecimal.valueOf(value).setScale(SCALE, RoundingMode.HALF_UP);
    }

    private BigDecimal nullableDecimal(Double value) {
        return value == null ? null : decimal(value);
    }
}
