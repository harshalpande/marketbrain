package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;

public record TradableEquityTrainingUniversePreview(
        String status,
        String universeContractVersion,
        String universeCode,
        String universeDefinition,
        LocalDate asOf,
        int minimumEligibleObservations,
        List<String> allowedSourceCodes,
        String providerPreference,
        int totalInstrumentCount,
        int activeNseInstrumentCount,
        int eligibleInstrumentCount,
        int insufficientHistoryCount,
        int staleCount,
        int noEligibleDataCount,
        int canonicalObservationCount,
        int eligibleObservationCount,
        int excludedObservationCount,
        LocalDate earliestObservationDate,
        LocalDate latestObservationDate,
        boolean currentTradableUniverse,
        boolean nifty500HistoricalMembershipRequired,
        boolean survivorshipRiskPresent,
        boolean prototypeTrainingUniverseReady,
        boolean benchmarkTrainingEligible,
        boolean pointInTimeSafe,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        String manifestHash,
        List<String> failedCheckpoints,
        List<TradableEquityTrainingUniverseItem> instruments,
        String detail
) {
}
