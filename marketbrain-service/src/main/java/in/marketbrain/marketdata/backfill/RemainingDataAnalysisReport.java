package in.marketbrain.marketdata.backfill;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record RemainingDataAnalysisReport(
        UUID jobId,
        int unresolvedFindingCount,
        int officialSessionFindingCount,
        int peerSessionFindingCount,
        int coverageGapFindingCount,
        int largeMoveFindingCount,
        int sourceRequestCount,
        int secondaryBackfillCandidateCount,
        int featureExclusionCandidateCount,
        int providerAdjustmentCandidateCount,
        int verifiedMoveCandidateCount,
        int keepOpenCount,
        int sourceFailureCount,
        boolean analysisComplete,
        String planHash,
        boolean candlesWritten,
        boolean resolutionsWritten,
        List<Item> items,
        String detail
) {
    public record Item(
            QualityFindingType findingType,
            String symbol,
            LocalDate findingDate,
            LocalDate relatedDate,
            String analysisStatus,
            QualityResolutionType recommendedResolutionType,
            LocalDate exclusionFrom,
            LocalDate exclusionTo,
            String officialSymbol,
            String matchBasis,
            String officialSeries,
            BigDecimal officialOpen,
            BigDecimal officialHigh,
            BigDecimal officialLow,
            BigDecimal officialClose,
            BigDecimal officialVolume,
            BigDecimal storedReturnPercent,
            BigDecimal officialReturnPercent,
            BigDecimal returnDifferencePercentagePoints,
            String evidenceSource,
            String evidenceUrl,
            String detail
    ) {
    }
}
