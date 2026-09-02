package in.marketbrain.marketdata.backfill;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record BackfillQualityReport(
        UUID jobId,
        String jobStatus,
        String qualityStatus,
        LocalDate requestedFrom,
        LocalDate requestedTo,
        int instrumentCount,
        long totalCandles,
        int blockingInstrumentCount,
        int reviewInstrumentCount,
        int duplicateRows,
        int invalidRows,
        int suspiciousGapCount,
        int largeMoveCount,
        int providerMismatchCount,
        int providerCheckFailureCount,
        int suspiciousGapThresholdDays,
        BigDecimal largeMoveThresholdPercent,
        boolean providerSpotCheckRequested,
        List<InstrumentQuality> instruments,
        List<GapFinding> suspiciousGaps,
        List<LargeMoveFinding> largeMoves,
        List<ProviderSpotCheck> providerSpotChecks,
        String detail
) {

    public record InstrumentQuality(
            String symbol,
            LocalDate firstCandleDate,
            LocalDate lastCandleDate,
            long candleCount,
            int leadingCoverageGapDays,
            int trailingCoverageGapDays,
            int longestCalendarGapDays,
            int suspiciousGapCount,
            int largeMoveCount,
            BigDecimal maximumAbsoluteCloseMovePercent,
            int duplicateRows,
            int invalidRows,
            String status
    ) {
    }

    public record GapFinding(
            String symbol,
            LocalDate previousTradingDate,
            LocalDate nextTradingDate,
            int calendarGapDays
    ) {
    }

    public record LargeMoveFinding(
            String symbol,
            LocalDate tradingDate,
            BigDecimal previousClose,
            BigDecimal close,
            BigDecimal absoluteMovePercent
    ) {
    }

    public record ProviderSpotCheck(
            String symbol,
            String status,
            LocalDate comparisonDate,
            BigDecimal storedClose,
            BigDecimal providerClose,
            BigDecimal differencePercent
    ) {
    }
}
