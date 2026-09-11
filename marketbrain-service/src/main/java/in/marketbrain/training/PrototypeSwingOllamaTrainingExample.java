package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingOllamaTrainingExample(
        String scenarioType,
        String symbol,
        BigDecimal dailyReturnPercent,
        BigDecimal sma20,
        BigDecimal sma50,
        BigDecimal sma200,
        BigDecimal rsi14,
        BigDecimal atr14,
        BigDecimal annualizedVolatility20Percent,
        BigDecimal volumeRatio20,
        BigDecimal rangePosition252Percent,
        BigDecimal targetNetReturnPercent,
        BigDecimal targetBenchmarkExcessReturnPercent,
        BigDecimal targetMaximumDrawdownPercent,
        String teachingPoint
) {
}
