package in.marketbrain.training;

import java.math.BigDecimal;
import java.time.LocalDate;

public record PrototypeSwingOllamaCandidate(
        String symbol,
        LocalDate effectiveAsOf,
        BigDecimal latestClose,
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
        BigDecimal rangePosition252Percent,
        BigDecimal netReturn5Sessions,
        BigDecimal netReturn20Sessions,
        BigDecimal netReturn60Sessions,
        BigDecimal benchmarkExcess5Sessions,
        BigDecimal benchmarkExcess20Sessions,
        BigDecimal benchmarkExcess60Sessions,
        BigDecimal maximumDrawdown5Sessions,
        BigDecimal maximumDrawdown20Sessions,
        BigDecimal maximumDrawdown60Sessions
) {
}
