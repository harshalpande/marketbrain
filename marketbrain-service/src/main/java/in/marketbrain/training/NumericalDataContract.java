package in.marketbrain.training;

import java.util.List;

/** Versioned review contract, not a fitted model or permission to train. */
public record NumericalDataContract(
        String version, String status, int horizonSessions, String decisionCutoff,
        String entryRule, String exitRule, String featureAvailabilityRule,
        List<String> candidateFeatures, List<String> forbiddenInputs,
        String splitRule, List<String> unresolvedGates, boolean trainingAuthorized) {
    public static NumericalDataContract draft() {
        return new NumericalDataContract(
                "NUMERICAL_SWING_20_V1_DRAFT", "CONTRACT_REVIEW_REQUIRED", 20,
                "16:00 Asia/Kolkata on a verified exchange session; bars/features must be available by cutoff",
                "Next exchange-session OPEN after decision; missing/non-executable entry censors row, never skip forward",
                "CLOSE of entry session + 19 exchange sessions; costs/slippage versioned separately",
                "Row needs source-availability proof at cutoff; current received_at/backfill alone is not historical vintage proof",
                List.of("dailyReturnPercent", "closeToSma20Percent", "closeToSma50Percent",
                        "closeToSma200Percent", "ema12ToEma26Percent", "rsi14", "atr14ToClosePercent",
                        "annualizedVolatility20Percent", "volumeRatio20", "rangePosition252Percent"),
                List.of("actualRank", "forwardReturn", "outcomeDate", "futureClassification",
                        "hindsightTrapSelection", "futureNews", "userApprovalAfterDecision"),
                "Group by decision date; chronological train/tune/untouched-test; purge overlapping label intervals; fit transforms on train only",
                List.of("EXCHANGE_CALENDAR_VERSION", "CORPORATE_ACTION_AND_EXECUTABLE_PRICE_POLICY",
                        "SOURCE_RIGHTS_AND_AVAILABILITY", "HISTORICAL_MEMBERSHIP_OR_RESTRICTED_RESEARCH_SCOPE",
                        "COST_AND_SLIPPAGE_POLICY", "MULTI_DATE_COVERAGE_AND_SPLIT_BOUNDARIES", "ROW_LEVEL_LEAKAGE_TESTS"), false);
    }
}
