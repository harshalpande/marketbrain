package in.marketbrain.training;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

@Service
public class PrototypeSwingOllamaScoreCalibrationPreviewService {

    static final String CALIBRATION_VERSION = "MARKETBRAIN_OLLAMA_SCORE_CALIBRATION_V1";

    private static final List<Integer> DEFAULT_CANDIDATE_LIMITS = List.of(5, 8, 12);
    private static final int MAXIMUM_CANDIDATE_LIMIT = 25;
    private static final int MINIMUM_EXPECTED_SCORE_SPREAD = 20;
    private static final int MINIMUM_STRONG_CANDIDATE_SCORE = 50;

    private final PrototypeSwingOllamaGuidedRankingEvaluationPreviewService evaluationService;

    public PrototypeSwingOllamaScoreCalibrationPreviewService(
            PrototypeSwingOllamaGuidedRankingEvaluationPreviewService evaluationService
    ) {
        this.evaluationService = evaluationService;
    }

    @Transactional(readOnly = true, timeout = 1800)
    public PrototypeSwingOllamaScoreCalibrationPreview preview(
            PrototypeSwingOllamaScoreCalibrationRequest request
    ) {
        PrototypeSwingOllamaScoreCalibrationRequest safeRequest = request == null
                ? new PrototypeSwingOllamaScoreCalibrationRequest(null, null, null, null)
                : request;
        String model = model(safeRequest.model());
        int horizon = horizon(safeRequest.rankingHorizonSessions());
        List<Integer> candidateLimits = candidateLimits(safeRequest.candidateLimits());
        List<PrototypeSwingOllamaScoreCalibrationBatch> batches = new ArrayList<>();

        for (int candidateLimit : candidateLimits) {
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation =
                    evaluationService.preview(new PrototypeSwingOllamaRankingRequest(
                            safeRequest.datasetRunId(),
                            model,
                            candidateLimit,
                            horizon
                    ));
            batches.add(batch(candidateLimit, evaluation));
        }

        List<String> aggregateFailures = aggregateFailures(batches);
        PrototypeSwingOllamaGuidedRankingEvaluationPreview firstEvaluation =
                batches.isEmpty() ? null : batches.getFirst().evaluationPreview();

        return new PrototypeSwingOllamaScoreCalibrationPreview(
                aggregateFailures.isEmpty() ? "REVIEW_REQUIRED" : "REVIEW_WITH_WARNINGS",
                firstEvaluation == null ? safeRequest.datasetRunId() : firstEvaluation.datasetRunId(),
                model,
                firstEvaluation == null ? null : firstEvaluation.asOf(),
                firstEvaluation == null ? null : firstEvaluation.labelThrough(),
                horizon,
                CALIBRATION_VERSION,
                candidateLimits,
                batches.size(),
                (int) batches.stream().filter(PrototypeSwingOllamaScoreCalibrationBatch::responseSchemaValid).count(),
                (int) batches.stream()
                        .filter(batch -> "SCORE_CALIBRATION_PASSED".equals(batch.scoreCalibrationStatus()))
                        .count(),
                (int) batches.stream()
                        .filter(batch -> "SCORE_CALIBRATION_WITH_WARNINGS".equals(batch.scoreCalibrationStatus()))
                        .count(),
                (int) batches.stream()
                        .filter(batch -> "SCORE_CALIBRATION_WEAK".equals(batch.scoreCalibrationStatus()))
                        .count(),
                batches.stream().mapToInt(batch -> batch.evaluationPreview().ollamaCallCount()).sum(),
                aggregateFailures,
                List.copyOf(batches),
                false,
                0,
                0,
                false,
                "Step 69 calibrated Ollama score usage across bounded candidate batches. "
                        + "This is an audit-only review; it creates no signal, paper fill, order, broker action, "
                        + "or live trading action."
        );
    }

    PrototypeSwingOllamaScoreCalibrationBatch batch(
            int candidateLimit,
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation
    ) {
        if (!evaluation.responseSchemaValid() || evaluation.candidateEvaluations().isEmpty()) {
            List<String> failures = new ArrayList<>();
            failures.add("SCHEMA_GUARDRAIL_BLOCKED");
            failures.addAll(evaluation.responseValidationFailures());
            return new PrototypeSwingOllamaScoreCalibrationBatch(
                    candidateLimit,
                    evaluation.candidateCount(),
                    evaluation.responseParseableJson(),
                    evaluation.responseSchemaValid(),
                    evaluation.rankingQualityStatus(),
                    "SCORE_CALIBRATION_BLOCKED",
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    evaluation.highConfidenceMissCount(),
                    evaluation.negativeReturnTopThreeCount(),
                    evaluation.weakReasonCount(),
                    List.copyOf(failures),
                    evaluation
            );
        }

        List<PrototypeSwingOllamaCandidateEvaluation> rows = evaluation.candidateEvaluations();
        int minimumScore = rows.stream()
                .mapToInt(PrototypeSwingOllamaCandidateEvaluation::ollamaScore)
                .min()
                .orElse(0);
        int maximumScore = rows.stream()
                .mapToInt(PrototypeSwingOllamaCandidateEvaluation::ollamaScore)
                .max()
                .orElse(0);
        PrototypeSwingOllamaCandidateEvaluation topScore = rows.stream()
                .max(Comparator
                        .comparingInt(PrototypeSwingOllamaCandidateEvaluation::ollamaScore)
                        .thenComparing(PrototypeSwingOllamaCandidateEvaluation::symbol))
                .orElseThrow();
        PrototypeSwingOllamaCandidateEvaluation bestActual = rows.stream()
                .min(Comparator
                        .comparingInt(PrototypeSwingOllamaCandidateEvaluation::actualRank)
                        .thenComparing(PrototypeSwingOllamaCandidateEvaluation::symbol))
                .orElseThrow();
        BigDecimal scoreRankCorrelation = scoreRankCorrelation(rows);
        List<String> failures = calibrationFailures(
                rows.size(),
                minimumScore,
                maximumScore,
                scoreRankCorrelation,
                topScore,
                bestActual,
                evaluation
        );

        return new PrototypeSwingOllamaScoreCalibrationBatch(
                candidateLimit,
                evaluation.candidateCount(),
                evaluation.responseParseableJson(),
                evaluation.responseSchemaValid(),
                evaluation.rankingQualityStatus(),
                scoreCalibrationStatus(failures),
                minimumScore,
                maximumScore,
                maximumScore - minimumScore,
                scoreRankCorrelation,
                topScore.symbol(),
                topScore.actualRank(),
                topScore.targetNetReturnPercent(),
                bestActual.symbol(),
                bestActual.ollamaScore(),
                bestActual.targetNetReturnPercent(),
                evaluation.highConfidenceMissCount(),
                evaluation.negativeReturnTopThreeCount(),
                evaluation.weakReasonCount(),
                failures,
                evaluation
        );
    }

    private List<String> calibrationFailures(
            int candidateCount,
            int minimumScore,
            int maximumScore,
            BigDecimal scoreRankCorrelation,
            PrototypeSwingOllamaCandidateEvaluation topScore,
            PrototypeSwingOllamaCandidateEvaluation bestActual,
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation
    ) {
        List<String> failures = new ArrayList<>();
        int scoreSpread = maximumScore - minimumScore;
        if (scoreSpread < MINIMUM_EXPECTED_SCORE_SPREAD) {
            failures.add("SCORE_SPREAD_TOO_COMPRESSED");
        }
        if (maximumScore < MINIMUM_STRONG_CANDIDATE_SCORE) {
            failures.add("SCORE_SCALE_UNDERUSED");
        }
        if (bestActual.ollamaScore() < MINIMUM_STRONG_CANDIDATE_SCORE) {
            failures.add("BEST_ACTUAL_SCORE_TOO_LOW");
        }
        if (topScore.actualRank() > Math.max(1, (int) Math.ceil(candidateCount / 2.0d))) {
            failures.add("TOP_SCORE_NOT_ACTUAL_TOP_HALF");
        }
        if (scoreRankCorrelation.compareTo(BigDecimal.ZERO) < 0) {
            failures.add("NEGATIVE_SCORE_RANK_CORRELATION");
        }
        if (evaluation.highConfidenceMissCount() > 0) {
            failures.add("HIGH_CONFIDENCE_MISS");
        }
        if (evaluation.negativeReturnTopThreeCount() > 0) {
            failures.add("NEGATIVE_RETURN_IN_OLLAMA_TOP_THREE");
        }
        return List.copyOf(failures);
    }

    private String scoreCalibrationStatus(List<String> failures) {
        if (failures.isEmpty()) {
            return "SCORE_CALIBRATION_PASSED";
        }
        if (failures.contains("SCORE_SCALE_UNDERUSED")
                || failures.contains("SCORE_SPREAD_TOO_COMPRESSED")
                || failures.contains("NEGATIVE_SCORE_RANK_CORRELATION")) {
            return "SCORE_CALIBRATION_WEAK";
        }
        return "SCORE_CALIBRATION_WITH_WARNINGS";
    }

    private List<String> aggregateFailures(List<PrototypeSwingOllamaScoreCalibrationBatch> batches) {
        Set<String> failures = new LinkedHashSet<>();
        for (PrototypeSwingOllamaScoreCalibrationBatch batch : batches) {
            for (String failure : batch.calibrationFailures()) {
                failures.add("LIMIT_" + batch.candidateLimit() + "_" + failure);
            }
        }
        return List.copyOf(failures);
    }

    private BigDecimal scoreRankCorrelation(List<PrototypeSwingOllamaCandidateEvaluation> rows) {
        List<PrototypeSwingOllamaCandidateEvaluation> sortedByScore = new ArrayList<>(rows);
        sortedByScore.sort(Comparator
                .comparingInt(PrototypeSwingOllamaCandidateEvaluation::ollamaScore)
                .reversed()
                .thenComparing(PrototypeSwingOllamaCandidateEvaluation::symbol));
        double sumRankDiffSquared = 0.0d;
        for (int index = 0; index < sortedByScore.size(); index++) {
            PrototypeSwingOllamaCandidateEvaluation row = sortedByScore.get(index);
            int scoreRank = index + 1;
            double diff = scoreRank - row.actualRank();
            sumRankDiffSquared += diff * diff;
        }
        int count = sortedByScore.size();
        double correlation = count < 2
                ? 1.0d
                : 1.0d - ((6.0d * sumRankDiffSquared) / (count * (Math.pow(count, 2.0d) - 1.0d)));
        return BigDecimal.valueOf(correlation).setScale(6, RoundingMode.HALF_UP);
    }

    private String model(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("model is required.");
        }
        String trimmed = value.trim();
        if (trimmed.length() > 80 || !trimmed.matches("^[A-Za-z0-9._:/-]+$")) {
            throw new IllegalArgumentException("model contains unsupported characters.");
        }
        return trimmed;
    }

    private int horizon(Integer value) {
        int horizon = value == null ? 20 : value;
        if (!SwingTrainingDatasetPreviewService.HORIZONS.contains(horizon)) {
            throw new IllegalArgumentException("rankingHorizonSessions must be one of 5, 20, or 60.");
        }
        return horizon;
    }

    private List<Integer> candidateLimits(List<Integer> requested) {
        List<Integer> source = requested == null || requested.isEmpty()
                ? DEFAULT_CANDIDATE_LIMITS
                : requested;
        Set<Integer> limits = new LinkedHashSet<>();
        for (Integer value : source) {
            if (value == null || value < 1 || value > MAXIMUM_CANDIDATE_LIMIT) {
                throw new IllegalArgumentException("candidateLimits must contain values between 1 and 25.");
            }
            limits.add(value);
        }
        if (limits.size() > 5) {
            throw new IllegalArgumentException("At most five candidate limits can be calibrated in one run.");
        }
        return List.copyOf(limits);
    }
}
