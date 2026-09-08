package in.marketbrain.feature;

import java.math.BigDecimal;

public record FeatureValues(
        BigDecimal previousClose,
        BigDecimal dailyReturnPercent,
        BigDecimal sma20,
        BigDecimal sma50,
        BigDecimal sma200,
        BigDecimal ema12,
        BigDecimal ema26,
        BigDecimal rsi14,
        BigDecimal atr14,
        BigDecimal annualizedVolatility20Percent,
        BigDecimal volumeRatio20,
        BigDecimal rangePosition252Percent
) {
}
