package in.marketbrain.training;

import java.math.BigDecimal;
import java.time.LocalDate;

public record SwingBenchmarkOutcome(
        int horizonSessions,
        LocalDate outcomeDate,
        int constituentLabelCount,
        BigDecimal equalWeightGrossReturnPercent
) {
}
