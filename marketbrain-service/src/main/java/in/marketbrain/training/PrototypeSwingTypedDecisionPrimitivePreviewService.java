package in.marketbrain.training;

import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@Service
public class PrototypeSwingTypedDecisionPrimitivePreviewService {

    static final String DECISION_CONTRACT_VERSION = "MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V1";
    static final String GRAMMAR_VERSION = "MARKETBRAIN_TYPED_DECISION_GBNF_V1";

    private static final int DEFAULT_CANDIDATE_LIMIT = 12;
    private static final int DEFAULT_RANKING_HORIZON_SESSIONS = 20;

    private static final List<String> DECISIONS = List.of("REJECT", "WATCHLIST", "SHORTLIST", "TOP_PICK");
    private static final List<String> RISK_BUCKETS = List.of("LOW", "MEDIUM", "HIGH", "BLOCKED");
    private static final List<String> TRAP_FLAGS = List.of("YES", "NO");
    private static final List<String> SCORE_BANDS = List.of("VERY_LOW", "LOW", "MEDIUM", "HIGH", "VERY_HIGH");
    private static final List<String> CONFIDENCE_BANDS = List.of("LOW", "MEDIUM", "HIGH");
    private static final List<String> REASON_CODES = List.of(
            "WEAK_TREND",
            "STRONG_MOMENTUM",
            "TRAP_RISK",
            "RELATIVE_STRENGTH",
            "RISK_ADJUSTED_LEADER",
            "JAVA_BASELINE_ALIGNED",
            "BLOCKED_BY_RISK",
            "RECOVERY_SETUP",
            "OVEREXTENSION_RISK",
            "MIXED_EVIDENCE"
    );

    private final PrototypeSwingTrainingDatasetAuditService auditService;
    private final PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService;

    public PrototypeSwingTypedDecisionPrimitivePreviewService(
            PrototypeSwingTrainingDatasetAuditService auditService,
            PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService
    ) {
        this.auditService = auditService;
        this.guidedRankingService = guidedRankingService;
    }

    public PrototypeSwingTypedDecisionPrimitivePreview preview(
            PrototypeSwingTypedDecisionPrimitiveRequest request
    ) {
        PrototypeSwingTypedDecisionPrimitiveRequest safeRequest = request == null
                ? new PrototypeSwingTypedDecisionPrimitiveRequest(null, null, null, null, null)
                : request;
        PrototypeSwingTrainingDatasetAudit audit = auditService.audit(safeRequest.datasetRunId());
        ensureAuditReady(audit);

        String selectionMode = selectionMode(safeRequest.selectionMode());
        int startOffset = startOffset(safeRequest.startOffset());
        int candidateLimit = candidateLimit(safeRequest.candidateLimit());
        int horizon = horizon(safeRequest.rankingHorizonSessions());
        UUID runId = audit.datasetRunId();
        List<PrototypeSwingOllamaCandidate> candidates =
                guidedRankingService.candidates(runId, startOffset, candidateLimit, selectionMode);
        Map<String, Integer> qualityAnchorRanks = guidedRankingService.qualityAnchorRanks(candidates);
        int leaderQualityAnchorScore = candidates.stream()
                .mapToInt(guidedRankingService::qualityAnchorScore)
                .max()
                .orElse(0);
        Map<String, Integer> actualRanks = actualRanks(candidates, horizon);
        List<PrototypeSwingTypedDecisionPrimitiveCandidate> items = new ArrayList<>();
        for (int index = 0; index < candidates.size(); index++) {
            PrototypeSwingOllamaCandidate candidate = candidates.get(index);
            int qualityAnchorRank = qualityAnchorRanks.get(candidate.symbol());
            int qualityAnchorScore = guidedRankingService.qualityAnchorScore(candidate);
            items.add(candidate(
                    index,
                    candidate,
                    horizon,
                    candidates.size(),
                    qualityAnchorRank,
                    qualityAnchorScore,
                    leaderQualityAnchorScore,
                    actualRanks.get(candidate.symbol())
            ));
        }
        return new PrototypeSwingTypedDecisionPrimitivePreview(
                "REVIEW_REQUIRED",
                runId,
                audit.asOf(),
                audit.labelThrough(),
                selectionMode,
                startOffset,
                candidateLimit,
                items.size(),
                horizon,
                DECISION_CONTRACT_VERSION,
                GRAMMAR_VERSION,
                grammar(),
                DECISIONS,
                RISK_BUCKETS,
                TRAP_FLAGS,
                SCORE_BANDS,
                CONFIDENCE_BANDS,
                REASON_CODES,
                List.copyOf(items),
                false,
                0,
                0,
                0,
                0,
                false,
                "Step 89 prepares real prototype swing candidates for a local llama.cpp/GBNF typed decision "
                        + "primitive. It does not call Ollama, llama.cpp, create signals, create paper fills, "
                        + "place orders, contact a broker, or perform database writes."
        );
    }

    private PrototypeSwingTypedDecisionPrimitiveCandidate candidate(
            int index,
            PrototypeSwingOllamaCandidate candidate,
            int horizon,
            int candidateCount,
            int qualityAnchorRank,
            int qualityAnchorScore,
            int leaderQualityAnchorScore,
            int actualRank
    ) {
        String decision = javaDecision(candidate, candidateCount, qualityAnchorRank, qualityAnchorScore);
        String riskBucket = javaRiskBucket(candidate, qualityAnchorScore);
        String trapDetected = javaTrapDetected(candidate, riskBucket, qualityAnchorScore);
        String scoreBand = javaScoreBand(candidate, decision, riskBucket, qualityAnchorScore);
        String confidenceBand = javaConfidenceBand(candidate, decision, riskBucket, qualityAnchorScore);
        String reasonCode = javaReasonCode(candidate, decision, riskBucket, qualityAnchorScore, leaderQualityAnchorScore);
        return new PrototypeSwingTypedDecisionPrimitiveCandidate(
                PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index),
                candidate.symbol(),
                prompt(candidate, index, horizon, qualityAnchorRank, qualityAnchorScore,
                        decision, riskBucket, trapDetected, scoreBand, confidenceBand, reasonCode),
                decision,
                riskBucket,
                trapDetected,
                scoreBand,
                confidenceBand,
                reasonCode,
                guidedRankingService.featurePriorScore(candidate),
                qualityAnchorScore,
                qualityAnchorRank,
                guidedRankingService.qualityAnchorBand(qualityAnchorRank, candidateCount, qualityAnchorScore),
                guidedRankingService.scoreCapHint(candidate),
                guidedRankingService.topPickEligibility(candidate),
                guidedRankingService.riskControlScore(candidate),
                guidedRankingService.opportunityScore(candidate),
                guidedRankingService.majorConflictCount(candidate),
                guidedRankingService.positiveSignalCount(candidate),
                guidedRankingService.trendTag(candidate),
                guidedRankingService.emaTag(candidate),
                guidedRankingService.rsiTag(candidate),
                guidedRankingService.volumeTag(candidate),
                guidedRankingService.volatilityTag(candidate),
                guidedRankingService.rangeTag(candidate),
                guidedRankingService.recoveryTag(candidate),
                guidedRankingService.overextensionTag(candidate),
                actualRank,
                targetNetReturn(candidate, horizon),
                targetBenchmarkExcessReturn(candidate, horizon),
                targetMaximumDrawdown(candidate, horizon)
        );
    }

    private String prompt(
            PrototypeSwingOllamaCandidate candidate,
            int index,
            int horizon,
            int qualityAnchorRank,
            int qualityAnchorScore,
            String javaDecision,
            String javaRiskBucket,
            String javaTrapDetected,
            String javaScoreBand,
            String javaConfidenceBand,
            String javaReasonCode
    ) {
        return """
                Return only JSON. You are MarketBrain's local typed decision primitive.
                Do not explain. Do not add markdown. Use only allowed enum values.
                Candidate id: %s
                Symbol: %s
                Decision choices: REJECT, WATCHLIST, SHORTLIST, TOP_PICK.
                Risk choices: LOW, MEDIUM, HIGH, BLOCKED.
                Trap choices: YES, NO.
                Score band choices: VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH.
                Confidence band choices: LOW, MEDIUM, HIGH.
                Reason code choices: WEAK_TREND, STRONG_MOMENTUM, TRAP_RISK, RELATIVE_STRENGTH, RISK_ADJUSTED_LEADER, JAVA_BASELINE_ALIGNED, BLOCKED_BY_RISK, RECOVERY_SETUP, OVEREXTENSION_RISK, MIXED_EVIDENCE.
                Java as-of features: featurePriorScore=%d; qualityAnchorScore=%d; qualityAnchorRank=%d; riskControlScore=%d; opportunityScore=%d; majorConflictCount=%d; positiveSignalCount=%d; scoreCapHint=%s; topPickEligibility=%s; trend=%s; ema=%s; rsi=%s; volume=%s; volatility=%s; range=%s; recovery=%s; overextension=%s.
                Java guardrail expectation for calibration: decision=%s; riskBucket=%s; trapDetected=%s; scoreBand=%s; confidenceBand=%s; primaryReasonCode=%s.
                Use the Java guardrail expectation unless the feature tags clearly indicate a safer lower-risk decision. Never upgrade BLOCKED or HARD_CAP candidates to TOP_PICK. This is a review-only prototype for horizon %d sessions.
                Required JSON keys: candidateId, decision, riskBucket, trapDetected, scoreBand, confidenceBand, primaryReasonCode.
                """.formatted(
                PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index),
                candidate.symbol(),
                guidedRankingService.featurePriorScore(candidate),
                qualityAnchorScore,
                qualityAnchorRank,
                guidedRankingService.riskControlScore(candidate),
                guidedRankingService.opportunityScore(candidate),
                guidedRankingService.majorConflictCount(candidate),
                guidedRankingService.positiveSignalCount(candidate),
                guidedRankingService.scoreCapHint(candidate),
                guidedRankingService.topPickEligibility(candidate),
                guidedRankingService.trendTag(candidate),
                guidedRankingService.emaTag(candidate),
                guidedRankingService.rsiTag(candidate),
                guidedRankingService.volumeTag(candidate),
                guidedRankingService.volatilityTag(candidate),
                guidedRankingService.rangeTag(candidate),
                guidedRankingService.recoveryTag(candidate),
                guidedRankingService.overextensionTag(candidate),
                javaDecision,
                javaRiskBucket,
                javaTrapDetected,
                javaScoreBand,
                javaConfidenceBand,
                javaReasonCode,
                horizon
        ).strip();
    }

    private String javaDecision(
            PrototypeSwingOllamaCandidate candidate,
            int candidateCount,
            int qualityAnchorRank,
            int qualityAnchorScore
    ) {
        if ("BLOCKED".equals(guidedRankingService.topPickEligibility(candidate)) || qualityAnchorScore < 35) {
            return "REJECT";
        }
        if (qualityAnchorRank == 1 && qualityAnchorScore >= 55
                && "HIGH_ELIGIBLE".equals(guidedRankingService.scoreCapHint(candidate))) {
            return "TOP_PICK";
        }
        int contenderCutoff = Math.max(2, (int) Math.ceil(candidateCount / 3.0d));
        if (qualityAnchorRank <= contenderCutoff && qualityAnchorScore >= 50) {
            return "SHORTLIST";
        }
        if (qualityAnchorScore >= 40) {
            return "WATCHLIST";
        }
        return "REJECT";
    }

    private String javaRiskBucket(PrototypeSwingOllamaCandidate candidate, int qualityAnchorScore) {
        if ("BLOCKED".equals(guidedRankingService.topPickEligibility(candidate))
                || "HARD_CAP_54".equals(guidedRankingService.scoreCapHint(candidate))) {
            return "BLOCKED";
        }
        if (guidedRankingService.majorConflictCount(candidate) >= 3
                || "VOLATILITY_HIGH".equals(guidedRankingService.volatilityTag(candidate))
                || qualityAnchorScore < 35) {
            return "HIGH";
        }
        if (guidedRankingService.majorConflictCount(candidate) >= 1
                || guidedRankingService.riskControlScore(candidate) < 60
                || "HARD_CAP_69".equals(guidedRankingService.scoreCapHint(candidate))) {
            return "MEDIUM";
        }
        return "LOW";
    }

    private String javaTrapDetected(
            PrototypeSwingOllamaCandidate candidate,
            String riskBucket,
            int qualityAnchorScore
    ) {
        if ("BLOCKED".equals(riskBucket)
                || "HIGH".equals(riskBucket)
                || "EXTREME_OVEREXTENSION".equals(guidedRankingService.overextensionTag(candidate))
                || guidedRankingService.majorConflictCount(candidate) >= 3
                || qualityAnchorScore < 35) {
            return "YES";
        }
        return "NO";
    }

    private String javaScoreBand(
            PrototypeSwingOllamaCandidate candidate,
            String decision,
            String riskBucket,
            int qualityAnchorScore
    ) {
        int cappedScore = qualityAnchorScore;
        if ("BLOCKED".equals(riskBucket) || "REJECT".equals(decision)) {
            cappedScore = Math.min(cappedScore, 30);
        } else if ("HARD_CAP_69".equals(guidedRankingService.scoreCapHint(candidate))) {
            cappedScore = Math.min(cappedScore, 69);
        } else if ("SOFT_CAP_84".equals(guidedRankingService.scoreCapHint(candidate))) {
            cappedScore = Math.min(cappedScore, 84);
        }
        if (cappedScore >= 75) {
            return "VERY_HIGH";
        }
        if (cappedScore >= 55) {
            return "HIGH";
        }
        if (cappedScore >= 40) {
            return "MEDIUM";
        }
        if (cappedScore >= 21) {
            return "LOW";
        }
        return "VERY_LOW";
    }

    private String javaConfidenceBand(
            PrototypeSwingOllamaCandidate candidate,
            String decision,
            String riskBucket,
            int qualityAnchorScore
    ) {
        if ("BLOCKED".equals(riskBucket)
                || ("REJECT".equals(decision) && guidedRankingService.majorConflictCount(candidate) >= 3)) {
            return "HIGH";
        }
        if (qualityAnchorScore >= 60 && guidedRankingService.positiveSignalCount(candidate) >= 3
                && guidedRankingService.majorConflictCount(candidate) <= 1) {
            return "HIGH";
        }
        if (qualityAnchorScore >= 45 || guidedRankingService.majorConflictCount(candidate) <= 2) {
            return "MEDIUM";
        }
        return "LOW";
    }

    private String javaReasonCode(
            PrototypeSwingOllamaCandidate candidate,
            String decision,
            String riskBucket,
            int qualityAnchorScore,
            int leaderQualityAnchorScore
    ) {
        if ("BLOCKED".equals(riskBucket)) {
            return "BLOCKED_BY_RISK";
        }
        if ("YES".equals(javaTrapDetected(candidate, riskBucket, qualityAnchorScore))) {
            return "TRAP_RISK";
        }
        if ("RECOVERY_CANDIDATE".equals(guidedRankingService.recoveryTag(candidate))) {
            return "RECOVERY_SETUP";
        }
        if ("EXTENDED".equals(guidedRankingService.overextensionTag(candidate))
                || "EXTREME_OVEREXTENSION".equals(guidedRankingService.overextensionTag(candidate))) {
            return "OVEREXTENSION_RISK";
        }
        if ("TOP_PICK".equals(decision)
                && Math.max(0, leaderQualityAnchorScore - qualityAnchorScore) <= 5) {
            return "RISK_ADJUSTED_LEADER";
        }
        if ("BULLISH_TREND".equals(guidedRankingService.trendTag(candidate))
                && guidedRankingService.positiveSignalCount(candidate) >= 3) {
            return "STRONG_MOMENTUM";
        }
        if ("TREND_CONFLICT".equals(guidedRankingService.trendTag(candidate))) {
            return "WEAK_TREND";
        }
        if (guidedRankingService.qualityAnchorScore(candidate) >= 45) {
            return "RELATIVE_STRENGTH";
        }
        return "MIXED_EVIDENCE";
    }

    private Map<String, Integer> actualRanks(List<PrototypeSwingOllamaCandidate> candidates, int horizon) {
        List<PrototypeSwingOllamaCandidate> sorted = new ArrayList<>(candidates);
        sorted.sort(Comparator
                .comparing((PrototypeSwingOllamaCandidate candidate) -> targetNetReturn(candidate, horizon),
                        Comparator.nullsLast(Comparator.reverseOrder()))
                .thenComparing(PrototypeSwingOllamaCandidate::symbol));
        java.util.LinkedHashMap<String, Integer> ranks = new java.util.LinkedHashMap<>();
        for (int index = 0; index < sorted.size(); index++) {
            ranks.put(sorted.get(index).symbol(), index + 1);
        }
        return ranks;
    }

    private BigDecimal targetNetReturn(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.netReturn5Sessions();
            case 60 -> candidate.netReturn60Sessions();
            default -> candidate.netReturn20Sessions();
        };
    }

    private BigDecimal targetBenchmarkExcessReturn(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.benchmarkExcess5Sessions();
            case 60 -> candidate.benchmarkExcess60Sessions();
            default -> candidate.benchmarkExcess20Sessions();
        };
    }

    private BigDecimal targetMaximumDrawdown(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.maximumDrawdown5Sessions();
            case 60 -> candidate.maximumDrawdown60Sessions();
            default -> candidate.maximumDrawdown20Sessions();
        };
    }

    private String grammar() {
        return """
                root ::= "{" ws "\\"candidateId\\"" ws ":" ws candidate-id ws "," ws "\\"decision\\"" ws ":" ws decision ws "," ws "\\"riskBucket\\"" ws ":" ws risk ws "," ws "\\"trapDetected\\"" ws ":" ws bool ws "," ws "\\"scoreBand\\"" ws ":" ws band ws "," ws "\\"confidenceBand\\"" ws ":" ws confidence ws "," ws "\\"primaryReasonCode\\"" ws ":" ws reason ws "}" ws
                candidate-id ::= "\\"CANDIDATE_" digit digit digit "\\""
                decision ::= "\\"REJECT\\"" | "\\"WATCHLIST\\"" | "\\"SHORTLIST\\"" | "\\"TOP_PICK\\""
                risk ::= "\\"LOW\\"" | "\\"MEDIUM\\"" | "\\"HIGH\\"" | "\\"BLOCKED\\""
                bool ::= "\\"YES\\"" | "\\"NO\\""
                band ::= "\\"VERY_LOW\\"" | "\\"LOW\\"" | "\\"MEDIUM\\"" | "\\"HIGH\\"" | "\\"VERY_HIGH\\""
                confidence ::= "\\"LOW\\"" | "\\"MEDIUM\\"" | "\\"HIGH\\""
                reason ::= "\\"WEAK_TREND\\"" | "\\"STRONG_MOMENTUM\\"" | "\\"TRAP_RISK\\"" | "\\"RELATIVE_STRENGTH\\"" | "\\"RISK_ADJUSTED_LEADER\\"" | "\\"JAVA_BASELINE_ALIGNED\\"" | "\\"BLOCKED_BY_RISK\\"" | "\\"RECOVERY_SETUP\\"" | "\\"OVEREXTENSION_RISK\\"" | "\\"MIXED_EVIDENCE\\""
                digit ::= [0-9]
                ws ::= [ \\t\\n]*
                """.strip();
    }

    private void ensureAuditReady(PrototypeSwingTrainingDatasetAudit audit) {
        if (audit == null
                || !"COMPLETED".equals(audit.status())
                || !audit.prototypeTrainingEligible()
                || !audit.pointInTimeSafe()
                || !audit.futureLabelsSeparated()
                || !audit.auditReadyForOllamaRanking()
                || audit.databaseWritesPerformed()
                || audit.ollamaCallCount() != 0
                || audit.signalsCreated() != 0
                || audit.ordersCreated() != 0
                || !audit.failedCheckpoints().isEmpty()) {
            throw new IllegalStateException("The prototype dataset audit is not ready for typed decision primitives.");
        }
    }

    private String selectionMode(String value) {
        if (value == null || value.isBlank()) {
            return "FIXED_SYMBOL";
        }
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        if (!List.of("FIXED_SYMBOL", "RANDOM_VALIDATION", "DIFFICULT_TRAPS", "RECOVERY_OVEREXTENSION")
                .contains(normalized)) {
            throw new IllegalArgumentException(
                    "selectionMode must be one of FIXED_SYMBOL, RANDOM_VALIDATION, DIFFICULT_TRAPS, or RECOVERY_OVEREXTENSION.");
        }
        return normalized;
    }

    private int startOffset(Integer value) {
        if (value == null) {
            return 0;
        }
        if (value < 0 || value > 500) {
            throw new IllegalArgumentException("startOffset must be between 0 and 500.");
        }
        return value;
    }

    private int candidateLimit(Integer value) {
        int limit = value == null ? DEFAULT_CANDIDATE_LIMIT : value;
        if (limit < 1 || limit > 24) {
            throw new IllegalArgumentException("candidateLimit must be between 1 and 24 for Step 89 preview.");
        }
        return limit;
    }

    private int horizon(Integer value) {
        int horizon = value == null ? DEFAULT_RANKING_HORIZON_SESSIONS : value;
        if (horizon != 5 && horizon != 20 && horizon != 60) {
            throw new IllegalArgumentException("rankingHorizonSessions must be one of 5, 20, or 60.");
        }
        return horizon;
    }
}
