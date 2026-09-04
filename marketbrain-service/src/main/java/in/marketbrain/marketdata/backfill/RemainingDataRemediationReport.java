package in.marketbrain.marketdata.backfill;

import java.util.List;
import java.util.UUID;

public record RemainingDataRemediationReport(
        UUID jobId,
        String planHash,
        String status,
        int totalItems,
        int pendingItems,
        int completedItems,
        int failedItems,
        int secondaryBackfillItems,
        int featureExclusionItems,
        int providerAdjustmentItems,
        int secondaryCandlesReady,
        long upstoxDailyCandleCount,
        long secondaryDailyCandleCount,
        long allSourceDailyCandleCount,
        int planResolutionsWritten,
        int currentResolutionCount,
        int unresolvedFindingCount,
        boolean workerEnabled,
        boolean finalProviderSpotCheckRequired,
        List<Failure> failures,
        String detail
) {
    public record Failure(
            String symbol,
            QualityFindingType findingType,
            java.time.LocalDate findingDate,
            String errorCode,
            String detail
    ) {
    }
}
