package in.marketbrain.training;

import java.math.BigDecimal;
import java.time.LocalDate;

public record PrototypeSwingTrainingHorizonAudit(
        int horizonSessions,
        int labelCount,
        LocalDate earliestOutcomeDate,
        LocalDate latestOutcomeDate,
        BigDecimal averageGrossReturnPercent,
        BigDecimal medianGrossReturnPercent,
        BigDecimal averageNetReturnPercent,
        BigDecimal medianNetReturnPercent,
        BigDecimal minimumNetReturnPercent,
        BigDecimal maximumNetReturnPercent,
        int positiveNetReturnCount,
        int negativeNetReturnCount,
        BigDecimal positiveNetReturnPercent,
        int benchmarkOutperformCount,
        BigDecimal benchmarkOutperformPercent,
        BigDecimal averageBenchmarkExcessReturnPercent,
        BigDecimal averageMaximumFavorableExcursionPercent,
        BigDecimal averageMaximumAdverseExcursionPercent,
        BigDecimal averageMaximumDrawdownPercent
) {
}
