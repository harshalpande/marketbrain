package in.marketbrain.marketdata.backfill;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record LargeMoveEvidenceReport(
        UUID jobId,
        int findingCount,
        int sourceRequestCount,
        int officialMatchCount,
        int officialAdjustedReturnMatchCount,
        int officialMismatchCount,
        int sourceUnavailableFindingCount,
        int symbolNotFoundCount,
        int corporateActionDateMatchCount,
        boolean resolutionsWritten,
        List<Item> findings,
        String detail
) {
    public record Item(
            String symbol,
            String isin,
            LocalDate findingDate,
            BigDecimal storedPreviousClose,
            BigDecimal storedClose,
            BigDecimal absoluteMovePercent,
            String evidenceStatus,
            String officialSymbol,
            String matchBasis,
            String officialSeries,
            BigDecimal officialPreviousClose,
            BigDecimal officialOpen,
            BigDecimal officialHigh,
            BigDecimal officialLow,
            BigDecimal officialClose,
            BigDecimal officialVolume,
            BigDecimal previousCloseDifferencePercent,
            BigDecimal closeDifferencePercent,
            BigDecimal storedReturnPercent,
            BigDecimal officialReturnPercent,
            BigDecimal returnDifferencePercentagePoints,
            BigDecimal previousCloseScaleRatio,
            BigDecimal closeScaleRatio,
            BigDecimal scaleRatioDifferencePercent,
            List<String> corporateActionTypes,
            String reviewPath,
            String sourceFormat,
            String sourceUrl,
            String detail
    ) {
    }
}
