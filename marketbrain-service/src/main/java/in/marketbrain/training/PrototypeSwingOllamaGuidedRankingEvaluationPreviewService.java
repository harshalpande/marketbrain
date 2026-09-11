package in.marketbrain.training;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@Service
public class PrototypeSwingOllamaGuidedRankingEvaluationPreviewService {

    static final String EVALUATION_VERSION = "MARKETBRAIN_OLLAMA_RANKING_EVALUATION_V1";

    private static final Set<String> FEATURE_KEYWORDS = Set.of(
            "daily", "return", "sma", "ema", "rsi", "atr", "volatility",
            "volume", "range", "drawdown", "benchmark", "trend", "momentum", "risk"
    );

    private final PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService;
    private final ObjectMapper objectMapper;

    public PrototypeSwingOllamaGuidedRankingEvaluationPreviewService(
            PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService,
            ObjectMapper objectMapper
    ) {
        this.guidedRankingService = guidedRankingService;
        this.objectMapper = objectMapper;
    }

    @Transactional(readOnly = true, timeout = 900)
    public PrototypeSwingOllamaGuidedRankingEvaluationPreview preview(
            PrototypeSwingOllamaRankingRequest request
    ) {
        PrototypeSwingOllamaGuidedRankingPreview guided = guidedRankingService.preview(request);
        return evaluateGuidedPreview(guided);
    }

    PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluateGuidedPreview(
            PrototypeSwingOllamaGuidedRankingPreview guided
    ) {
        if (!guided.responseParseableJson() || !guided.responseSchemaValid()) {
            return blocked(guided);
        }
        Evaluation evaluation = evaluateRankQuality(guided);
        List<String> failures = evaluationFailures(guided.candidateCount(), evaluation);

        return new PrototypeSwingOllamaGuidedRankingEvaluationPreview(
                "REVIEW_REQUIRED",
                guided.datasetRunId(),
                guided.datasetContractVersion(),
                guided.sourceUniverseCode(),
                guided.asOf(),
                guided.labelThrough(),
                guided.datasetManifestHash(),
                guided.model(),
                guided.candidateCount(),
                guided.trainingExampleCount(),
                guided.rankingHorizonSessions(),
                guided.instructionPackVersion(),
                guided.responseSchemaVersion(),
                guided.rubricVersion(),
                EVALUATION_VERSION,
                guided.playbookHash(),
                guided.promptHash(),
                guided.responseHash(),
                guided.responseParseableJson(),
                guided.responseSchemaValid(),
                guided.responseValidationFailures(),
                rankingQualityStatus(failures),
                evaluation.topPickSymbol(),
                evaluation.topPickActualRank(),
                evaluation.topPickNetReturnPercent(),
                evaluation.bestActualSymbol(),
                evaluation.bestActualOllamaRank(),
                evaluation.bestActualNetReturnPercent(),
                evaluation.topThreeOverlapCount(),
                decimal(evaluation.rankCorrelationScore()),
                evaluation.highConfidenceMissCount(),
                evaluation.negativeReturnTopThreeCount(),
                evaluation.weakReasonCount(),
                failures,
                evaluation.candidateEvaluations(),
                guided,
                guided.dailyFreshDataFeedbackLoopDesigned(),
                guided.dailyFreshDataUsedForTraining(),
                guided.survivorshipRiskPresent(),
                guided.prototypeTrainingEligible(),
                guided.benchmarkTrainingEligible(),
                guided.pointInTimeSafe(),
                guided.futureLabelsSeparated(),
                false,
                guided.ollamaCallCount(),
                0,
                0,
                false,
                "Step 68 evaluated the guided Ollama ranking against hidden future labels. "
                        + "This is an audit-only quality review; it creates no signal, paper fill, order, "
                        + "broker action, or live trading action."
        );
    }

    private PrototypeSwingOllamaGuidedRankingEvaluationPreview blocked(
            PrototypeSwingOllamaGuidedRankingPreview guided
    ) {
        return new PrototypeSwingOllamaGuidedRankingEvaluationPreview(
                "REVIEW_BLOCKED",
                guided.datasetRunId(),
                guided.datasetContractVersion(),
                guided.sourceUniverseCode(),
                guided.asOf(),
                guided.labelThrough(),
                guided.datasetManifestHash(),
                guided.model(),
                guided.candidateCount(),
                guided.trainingExampleCount(),
                guided.rankingHorizonSessions(),
                guided.instructionPackVersion(),
                guided.responseSchemaVersion(),
                guided.rubricVersion(),
                EVALUATION_VERSION,
                guided.playbookHash(),
                guided.promptHash(),
                guided.responseHash(),
                guided.responseParseableJson(),
                guided.responseSchemaValid(),
                guided.responseValidationFailures(),
                "SCHEMA_GUARDRAIL_BLOCKED",
                null,
                null,
                null,
                null,
                null,
                null,
                0,
                null,
                0,
                0,
                0,
                List.of("RESPONSE_SCHEMA_INVALID"),
                List.of(),
                guided,
                guided.dailyFreshDataFeedbackLoopDesigned(),
                guided.dailyFreshDataUsedForTraining(),
                guided.survivorshipRiskPresent(),
                guided.prototypeTrainingEligible(),
                guided.benchmarkTrainingEligible(),
                guided.pointInTimeSafe(),
                guided.futureLabelsSeparated(),
                false,
                guided.ollamaCallCount(),
                0,
                0,
                false,
                "Ollama output was not evaluated for ranking quality because schema guardrails blocked it first."
        );
    }

    private Evaluation evaluateRankQuality(PrototypeSwingOllamaGuidedRankingPreview guided) {
        JsonNode ranked = rankedCandidates(guided.ollamaResponse());
        Map<String, PrototypeSwingOllamaCandidate> candidatesById = new HashMap<>();
        Map<String, PrototypeSwingOllamaCandidate> candidatesBySymbol = new HashMap<>();
        for (int index = 0; index < guided.candidates().size(); index++) {
            PrototypeSwingOllamaCandidate candidate = guided.candidates().get(index);
            candidatesById.put(PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index), candidate);
            candidatesBySymbol.put(candidate.symbol(), candidate);
        }
        Map<String, Integer> actualRanks = actualRanks(guided.candidates(), guided.rankingHorizonSessions());
        Set<String> actualTopThree = topSymbols(actualRanks, 3);

        List<PrototypeSwingOllamaCandidateEvaluation> evaluations = new ArrayList<>();
        String topPickSymbol = null;
        Integer topPickActualRank = null;
        BigDecimal topPickNetReturn = null;
        String bestActualSymbol = null;
        Integer bestActualOllamaRank = null;
        BigDecimal bestActualNetReturn = null;
        int topThreeOverlap = 0;
        int highConfidenceMissCount = 0;
        int negativeReturnTopThreeCount = 0;
        int weakReasonCount = 0;
        double sumRankDiffSquared = 0.0d;

        List<JsonNode> rankedNodes = new ArrayList<>();
        ranked.forEach(rankedNodes::add);
        rankedNodes.sort(Comparator.comparingInt(node -> node.path("rank").asInt(Integer.MAX_VALUE)));

        for (JsonNode node : rankedNodes) {
            String candidateId = node.path("candidateId").asText("");
            String symbol = node.path("symbol").asText("");
            PrototypeSwingOllamaCandidate candidate = candidatesById.get(candidateId);
            if (candidate == null) {
                candidate = candidatesBySymbol.get(symbol);
            }
            if (candidate == null) {
                continue;
            }
            symbol = candidate.symbol();
            int ollamaRank = node.path("rank").asInt();
            int actualRank = actualRanks.get(symbol);
            int rankError = Math.abs(ollamaRank - actualRank);
            int score = node.path("score").asInt();
            String confidence = node.path("confidence").asText("");
            BigDecimal netReturn = netReturn(candidate, guided.rankingHorizonSessions());
            BigDecimal benchmarkExcess = benchmarkExcess(candidate, guided.rankingHorizonSessions());
            BigDecimal drawdown = maximumDrawdown(candidate, guided.rankingHorizonSessions());
            String reason = node.path("reason").asText("");
            boolean featureReason = reasonMentionsKnownFeature(reason, node.path("positiveEvidence"), node.path("riskFlags"));
            boolean highConfidenceMiss = "HIGH".equals(confidence)
                    && actualRank > Math.max(2, (int) Math.ceil(guided.candidateCount() / 2.0d));
            boolean negativeReturnTopThree = ollamaRank <= 3 && netReturn.signum() < 0;
            if (highConfidenceMiss) {
                highConfidenceMissCount++;
            }
            if (negativeReturnTopThree) {
                negativeReturnTopThreeCount++;
            }
            if (!featureReason) {
                weakReasonCount++;
            }
            if (ollamaRank == 1) {
                topPickSymbol = symbol;
                topPickActualRank = actualRank;
                topPickNetReturn = netReturn;
            }
            if (actualRank == 1) {
                bestActualSymbol = symbol;
                bestActualOllamaRank = ollamaRank;
                bestActualNetReturn = netReturn;
            }
            if (ollamaRank <= 3 && actualTopThree.contains(symbol)) {
                topThreeOverlap++;
            }
            double diff = ollamaRank - actualRank;
            sumRankDiffSquared += diff * diff;
            evaluations.add(new PrototypeSwingOllamaCandidateEvaluation(
                    symbol,
                    ollamaRank,
                    actualRank,
                    rankError,
                    score,
                    confidence,
                    netReturn,
                    benchmarkExcess,
                    drawdown,
                    qualityBucket(actualRank, guided.candidateCount()),
                    highConfidenceMiss,
                    negativeReturnTopThree,
                    featureReason,
                    reason
            ));
        }

        return new Evaluation(
                topPickSymbol,
                topPickActualRank,
                topPickNetReturn,
                bestActualSymbol,
                bestActualOllamaRank,
                bestActualNetReturn,
                topThreeOverlap,
                rankCorrelation(guided.candidateCount(), sumRankDiffSquared),
                highConfidenceMissCount,
                negativeReturnTopThreeCount,
                weakReasonCount,
                List.copyOf(evaluations)
        );
    }

    private JsonNode rankedCandidates(String response) {
        try {
            return objectMapper.readTree(response).path("rankedCandidates");
        } catch (Exception exception) {
            throw new IllegalStateException("Guided Ollama response was not parseable during evaluation.", exception);
        }
    }

    private Map<String, Integer> actualRanks(
            List<PrototypeSwingOllamaCandidate> candidates,
            int horizon
    ) {
        List<PrototypeSwingOllamaCandidate> sorted = new ArrayList<>(candidates);
        sorted.sort(Comparator
                .comparing((PrototypeSwingOllamaCandidate candidate) -> netReturn(candidate, horizon))
                .reversed()
                .thenComparing(PrototypeSwingOllamaCandidate::symbol));
        Map<String, Integer> ranks = new HashMap<>();
        for (int index = 0; index < sorted.size(); index++) {
            ranks.put(sorted.get(index).symbol(), index + 1);
        }
        return ranks;
    }

    private Set<String> topSymbols(Map<String, Integer> ranks, int limit) {
        Set<String> result = new HashSet<>();
        for (Map.Entry<String, Integer> entry : ranks.entrySet()) {
            if (entry.getValue() <= limit) {
                result.add(entry.getKey());
            }
        }
        return result;
    }

    private List<String> evaluationFailures(int candidateCount, Evaluation evaluation) {
        List<String> failures = new ArrayList<>();
        int acceptableTopPickRank = Math.max(1, (int) Math.ceil(candidateCount / 2.0d));
        if (evaluation.topPickActualRank() == null || evaluation.topPickActualRank() > acceptableTopPickRank) {
            failures.add("TOP_PICK_NOT_IN_ACTUAL_TOP_HALF");
        }
        if (evaluation.bestActualOllamaRank() == null || evaluation.bestActualOllamaRank() > 3) {
            failures.add("BEST_ACTUAL_NOT_IN_OLLAMA_TOP_THREE");
        }
        if (evaluation.topThreeOverlapCount() < 1) {
            failures.add("NO_TOP_THREE_OVERLAP");
        }
        if (evaluation.rankCorrelationScore() < 0.0d) {
            failures.add("NEGATIVE_RANK_CORRELATION");
        }
        if (evaluation.highConfidenceMissCount() > 0) {
            failures.add("HIGH_CONFIDENCE_MISS");
        }
        if (evaluation.negativeReturnTopThreeCount() > 0) {
            failures.add("NEGATIVE_RETURN_IN_OLLAMA_TOP_THREE");
        }
        if (evaluation.weakReasonCount() > 0) {
            failures.add("VAGUE_REASONING");
        }
        return List.copyOf(failures);
    }

    private String rankingQualityStatus(List<String> failures) {
        if (failures.isEmpty()) {
            return "QUALITY_REVIEW_PASSED";
        }
        if (failures.contains("TOP_PICK_NOT_IN_ACTUAL_TOP_HALF")
                || failures.contains("NO_TOP_THREE_OVERLAP")
                || failures.contains("NEGATIVE_RANK_CORRELATION")) {
            return "QUALITY_REVIEW_WEAK";
        }
        return "QUALITY_REVIEW_WITH_WARNINGS";
    }

    private boolean reasonMentionsKnownFeature(
            String reason,
            JsonNode positiveEvidence,
            JsonNode riskFlags
    ) {
        StringBuilder text = new StringBuilder(reason == null ? "" : reason);
        positiveEvidence.forEach(node -> text.append(' ').append(node.asText("")));
        riskFlags.forEach(node -> text.append(' ').append(node.asText("")));
        String normalized = text.toString().toLowerCase(Locale.ROOT);
        for (String keyword : FEATURE_KEYWORDS) {
            if (normalized.contains(keyword)) {
                return true;
            }
        }
        return false;
    }

    private String qualityBucket(int actualRank, int candidateCount) {
        int topCutoff = Math.max(1, (int) Math.ceil(candidateCount / 3.0d));
        int bottomCutoff = Math.max(1, (int) Math.floor(candidateCount * 2.0d / 3.0d));
        if (actualRank <= topCutoff) {
            return "ACTUAL_TOP_TIER";
        }
        if (actualRank > bottomCutoff) {
            return "ACTUAL_BOTTOM_TIER";
        }
        return "ACTUAL_MIDDLE_TIER";
    }

    private double rankCorrelation(int candidateCount, double sumRankDiffSquared) {
        if (candidateCount < 2) {
            return 1.0d;
        }
        return 1.0d - ((6.0d * sumRankDiffSquared)
                / (candidateCount * (Math.pow(candidateCount, 2.0d) - 1.0d)));
    }

    private BigDecimal netReturn(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.netReturn5Sessions();
            case 20 -> candidate.netReturn20Sessions();
            case 60 -> candidate.netReturn60Sessions();
            default -> throw new IllegalArgumentException("Unsupported horizon: " + horizon);
        };
    }

    private BigDecimal benchmarkExcess(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.benchmarkExcess5Sessions();
            case 20 -> candidate.benchmarkExcess20Sessions();
            case 60 -> candidate.benchmarkExcess60Sessions();
            default -> throw new IllegalArgumentException("Unsupported horizon: " + horizon);
        };
    }

    private BigDecimal maximumDrawdown(PrototypeSwingOllamaCandidate candidate, int horizon) {
        return switch (horizon) {
            case 5 -> candidate.maximumDrawdown5Sessions();
            case 20 -> candidate.maximumDrawdown20Sessions();
            case 60 -> candidate.maximumDrawdown60Sessions();
            default -> throw new IllegalArgumentException("Unsupported horizon: " + horizon);
        };
    }

    private BigDecimal decimal(double value) {
        return BigDecimal.valueOf(value).setScale(6, RoundingMode.HALF_UP);
    }

    private record Evaluation(
            String topPickSymbol,
            Integer topPickActualRank,
            BigDecimal topPickNetReturnPercent,
            String bestActualSymbol,
            Integer bestActualOllamaRank,
            BigDecimal bestActualNetReturnPercent,
            int topThreeOverlapCount,
            double rankCorrelationScore,
            int highConfidenceMissCount,
            int negativeReturnTopThreeCount,
            int weakReasonCount,
            List<PrototypeSwingOllamaCandidateEvaluation> candidateEvaluations
    ) {
    }
}
