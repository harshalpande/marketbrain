package in.marketbrain.training;

import java.math.BigDecimal;
import java.time.LocalDate;

public record SwingOutcomeLabel(
        int horizonSessions,
        LocalDate outcomeDate,
        BigDecimal grossReturnPercent,
        BigDecimal assumedRoundTripCostPercent,
        BigDecimal netReturnPercent,
        BigDecimal maximumFavorableExcursionPercent,
        BigDecimal maximumAdverseExcursionPercent,
        BigDecimal maximumDrawdownPercent,
        BigDecimal benchmarkProxyReturnPercent,
        BigDecimal benchmarkExcessReturnPercent
) {
    SwingOutcomeLabel withBenchmark(BigDecimal benchmarkReturn) {
        return new SwingOutcomeLabel(
                horizonSessions,
                outcomeDate,
                grossReturnPercent,
                assumedRoundTripCostPercent,
                netReturnPercent,
                maximumFavorableExcursionPercent,
                maximumAdverseExcursionPercent,
                maximumDrawdownPercent,
                benchmarkReturn,
                grossReturnPercent.subtract(benchmarkReturn)
        );
    }
}
