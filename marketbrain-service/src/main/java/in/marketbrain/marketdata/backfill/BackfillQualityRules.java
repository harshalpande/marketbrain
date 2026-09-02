package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

@Component
public class BackfillQualityRules {

    public String instrumentStatus(
            long candleCount,
            int duplicateRows,
            int invalidRows,
            int leadingCoverageGapDays,
            int trailingCoverageGapDays,
            int suspiciousGapCount,
            int largeMoveCount,
            int suspiciousGapThresholdDays
    ) {
        if (candleCount == 0 || duplicateRows > 0 || invalidRows > 0) {
            return "BLOCKED";
        }
        if (leadingCoverageGapDays > suspiciousGapThresholdDays
                || trailingCoverageGapDays > suspiciousGapThresholdDays
                || suspiciousGapCount > 0
                || largeMoveCount > 0) {
            return "REVIEW";
        }
        return "PASS";
    }

    public String overallStatus(
            int instrumentCount,
            int blockingInstrumentCount,
            int reviewInstrumentCount,
            int providerMismatchCount,
            int providerCheckFailureCount
    ) {
        if (instrumentCount == 0 || blockingInstrumentCount > 0) {
            return "BLOCKED";
        }
        if (reviewInstrumentCount > 0 || providerMismatchCount > 0 || providerCheckFailureCount > 0) {
            return "REVIEW";
        }
        return "PASS";
    }
}
