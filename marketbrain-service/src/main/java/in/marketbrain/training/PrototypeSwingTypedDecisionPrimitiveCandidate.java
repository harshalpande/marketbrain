package in.marketbrain.training;

import java.math.BigDecimal;

public record PrototypeSwingTypedDecisionPrimitiveCandidate(
        String candidateId,
        String symbol,
        String prompt,
        String javaDecision,
        String javaRiskBucket,
        String javaTrapDetected,
        String javaScoreBand,
        String javaConfidenceBand,
        String javaPrimaryReasonCode,
        int javaFeaturePriorScore,
        int javaQualityAnchorScore,
        int javaQualityAnchorRank,
        String javaQualityAnchorBand,
        String javaScoreCapHint,
        String javaTopPickEligibility,
        int javaRiskControlScore,
        int javaOpportunityScore,
        int javaMajorConflictCount,
        int javaPositiveSignalCount,
        String trendTag,
        String emaTag,
        String rsiTag,
        String volumeTag,
        String volatilityTag,
        String rangeTag,
        String recoveryTag,
        String overextensionTag,
        int actualRank,
        BigDecimal targetNetReturnPercent,
        BigDecimal targetBenchmarkExcessReturnPercent,
        BigDecimal targetMaximumDrawdownPercent,
        String independentPrompt,
        String evidenceCategory,
        String hardExclusionReason
) {
}
