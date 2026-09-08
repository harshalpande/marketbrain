package in.marketbrain.feature;

import java.math.BigDecimal;
import java.time.LocalDate;

record FeatureCandle(
        LocalDate tradingDate,
        String source,
        BigDecimal open,
        BigDecimal high,
        BigDecimal low,
        BigDecimal close,
        BigDecimal volume,
        boolean excluded
) {
}
