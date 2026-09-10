package in.marketbrain.training;

import java.time.LocalDate;

public record TradableEquityTrainingUniverseItem(
        long instrumentId,
        String symbol,
        String isin,
        String displayName,
        String status,
        LocalDate firstCandleDate,
        LocalDate latestCandleDate,
        int canonicalObservationCount,
        int eligibleObservationCount,
        int excludedObservationCount,
        String latestSource,
        String detail
) {
}
