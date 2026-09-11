package in.marketbrain.training;

import java.math.BigDecimal;
import java.time.LocalDate;

public record PrototypeSwingTrainingExtremeOutcome(
        int horizonSessions,
        String symbol,
        LocalDate outcomeDate,
        BigDecimal grossReturnPercent,
        BigDecimal netReturnPercent,
        BigDecimal benchmarkExcessReturnPercent,
        BigDecimal maximumFavorableExcursionPercent,
        BigDecimal maximumAdverseExcursionPercent,
        BigDecimal maximumDrawdownPercent
) {
}
