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
        int missingProviderDataInstrumentCount,
        int reviewInstrumentCount,
        int duplicateRows,
        int invalidRows,
        int suspiciousGapCount,
        int largeMoveCount,
        int providerMismatchCount,
        int providerCheckFailureCount,
        int officialSpecialSessionCount,
        int missingOfficialSessionCount,
        int unresolvedMissingOfficialSessionCount,
        int peerConfirmedSessionCount,
        int missingPeerConfirmedSessionCount,
        int unresolvedMissingPeerConfirmedSessionCount,
        int unresolvedSuspiciousGapCount,
        int unresolvedLargeMoveCount,
        int resolvedFindingCount,
        int documentedFindingCount,
        int unresolvedFindingCount,
        int truncatedFindingCount,
        long mutuallyAvailableTradingDateCount,
        int suspiciousGapThresholdDays,
        BigDecimal largeMoveThresholdPercent,
        boolean providerSpotCheckRequested,
        boolean modelTrainingEligible,
        boolean backtestingEligible,
        List<String> eligibilityReasons,
        List<InstrumentQuality> instruments,
        List<OfficialSessionCoverage> officialSessionCoverage,
        List<MissingSessionFinding> missingOfficialSessions,
        List<MissingSessionFinding> missingPeerConfirmedSessions,
        List<GapFinding> suspiciousGaps,
        List<LargeMoveFinding> largeMoves,
        List<QualityFinding> qualityFindings,
        List<QualityResolutionRecord> currentResolutions,
        List<ProviderSpotCheck> providerSpotChecks,
        String detail
) {

    public record InstrumentQuality(
            String symbol,
            LocalDate firstCandleDate,
            LocalDate lastCandleDate,
            long candleCount,
            int missingOfficialSessionCount,
            int missingPeerConfirmedSessionCount,
            int unresolvedMissingOfficialSessionCount,
            int unresolvedMissingPeerConfirmedSessionCount,
            int leadingCoverageGapDays,
            int trailingCoverageGapDays,
            int longestCalendarGapDays,
            int suspiciousGapCount,
            int largeMoveCount,
            int unresolvedSuspiciousGapCount,
            int unresolvedLargeMoveCount,
            BigDecimal maximumAbsoluteCloseMovePercent,
            int duplicateRows,
            int invalidRows,
            String status
    ) {
    }

    public record OfficialSessionCoverage(
            LocalDate tradingDate,
            String sessionType,
            String sessionName,
            int eligibleInstrumentCount,
            int presentInstrumentCount,
            int missingInstrumentCount,
            String status,
            String sourceUrl
    ) {
    }

    public record MissingSessionFinding(
            String symbol,
            LocalDate tradingDate,
            String sessionType,
            String sessionName,
            String evidenceType,
            String status,
            String sourceUrl
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

    public record QualityFinding(
            QualityFindingType findingType,
            String symbol,
            LocalDate findingDate,
            LocalDate relatedDate,
            String rawStatus,
            String reviewStatus,
            QualityResolutionType resolutionType,
            boolean allowsTraining,
            LocalDate exclusionFrom,
            LocalDate exclusionTo,
            String evidenceSource,
            String evidenceUrl,
            List<String> corporateActionTypes
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
