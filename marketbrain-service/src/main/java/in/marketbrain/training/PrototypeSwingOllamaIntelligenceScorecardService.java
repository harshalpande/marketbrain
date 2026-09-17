package in.marketbrain.training;

import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
public class PrototypeSwingOllamaIntelligenceScorecardService {

    static final String SCORECARD_VERSION = "MARKETBRAIN_GRANITE_INTELLIGENCE_SCORECARD_V1";

    public PrototypeSwingOllamaIntelligenceScorecard scorecard(
            PrototypeSwingOllamaChunkedRankingPreview preview
    ) {
        if (preview == null) {
            throw new IllegalArgumentException("chunked ranking preview is required.");
        }
        if (preview.chunkCount() <= 0 || preview.chunks() == null || preview.chunks().isEmpty()) {
            throw new IllegalArgumentException("chunked ranking preview must contain at least one chunk.");
        }

        List<PrototypeSwingOllamaIntelligenceScorecardChunk> chunkScores = preview.chunks().stream()
                .sorted(Comparator.comparingInt(PrototypeSwingOllamaChunkedRankingChunk::chunkNumber))
                .map(this::chunkScore)
                .toList();

        int chunkCount = preview.chunkCount();
        int usableChunks = preview.passedChunkCount() + preview.warningChunkCount();
        int pipelineReliability = percent(usableChunks, chunkCount);
        int cleanPass = percent(preview.passedChunkCount(), chunkCount);
        int schemaDiscipline = average(chunkScores.stream()
                .mapToInt(chunk -> chunk.acceptedSchemaValid() && chunk.warnings().stream()
                        .noneMatch(warning -> warning.startsWith("VALIDATION:"))
                        ? 100
                        : 0)
                .toArray());
        int calibration = average(chunkScores.stream()
                .mapToInt(chunk -> statusScore(chunk.acceptedScoreCalibrationStatus()))
                .toArray());
        int ranking = average(chunkScores.stream()
                .mapToInt(chunk -> statusScore(chunk.acceptedRankingQualityStatus()))
                .toArray());
        int finalistQuality = average(chunkScores.stream()
                .mapToInt(this::finalistQualityScore)
                .toArray());
        int overall = clamp((int) Math.round(
                (pipelineReliability * 0.20d)
                        + (schemaDiscipline * 0.15d)
                        + (calibration * 0.20d)
                        + (ranking * 0.25d)
                        + (finalistQuality * 0.20d)));

        List<PrototypeSwingOllamaIntelligenceScorecardDimension> dimensions = List.of(
                dimension("PIPELINE_RELIABILITY", pipelineReliability,
                        "Usable chunks %d/%d, failed chunks %d."
                                .formatted(usableChunks, chunkCount, preview.failedChunkCount())),
                dimension("SCHEMA_DISCIPLINE", schemaDiscipline,
                        "Accepted attempts with valid schema and no validation failures."),
                dimension("SCORE_CALIBRATION", calibration,
                        "Accepted attempt score calibration statuses."),
                dimension("RANKING_QUALITY", ranking,
                        "Accepted attempt ranking quality statuses."),
                dimension("FINALIST_QUALITY", finalistQuality,
                        "Top finalist actual rank, negative-return avoidance and finalist usefulness."));

        int negativeReturnTopPickCount = (int) chunkScores.stream()
                .filter(chunk -> chunk.warnings().stream().anyMatch("EVALUATION:NEGATIVE_RETURN_IN_OLLAMA_TOP_THREE"::equals))
                .count();
        int weakTopPickCount = (int) chunkScores.stream()
                .filter(chunk -> chunk.warnings().stream().anyMatch("EVALUATION:TOP_PICK_NOT_IN_ACTUAL_TOP_HALF"::equals))
                .count();

        return new PrototypeSwingOllamaIntelligenceScorecard(
                status(overall, preview.failedChunkCount()),
                preview.datasetRunId(),
                preview.model(),
                preview.selectionMode(),
                preview.startOffset(),
                preview.totalCandidateLimit(),
                preview.chunkSize(),
                chunkCount,
                preview.processedCandidateCount(),
                preview.finalistCount(),
                preview.ollamaCallCount(),
                overall,
                100 - overall,
                maturityBand(overall, preview.failedChunkCount()),
                pipelineReliability,
                cleanPass,
                schemaDiscipline,
                calibration,
                ranking,
                finalistQuality,
                preview.failedChunkCount(),
                preview.warningChunkCount(),
                preview.passedChunkCount(),
                preview.warningChunkCount(),
                negativeReturnTopPickCount,
                weakTopPickCount,
                dimensions,
                chunkScores,
                topImprovementActions(preview, calibration, ranking, finalistQuality, cleanPass,
                        negativeReturnTopPickCount, weakTopPickCount),
                List.of(
                        "Review-only scorecard: no Ollama call is made.",
                        "No database write, signal, paper fill, order, broker action, or live trading action is created.",
                        "Java remains the final arbiter; Granite is evaluated as a bounded reviewer."),
                false,
                0,
                0,
                false,
                "Granite intelligence scorecard %s computed from a completed chunked ranking review."
                        .formatted(SCORECARD_VERSION));
    }

    private PrototypeSwingOllamaIntelligenceScorecardChunk chunkScore(
            PrototypeSwingOllamaChunkedRankingChunk chunk
    ) {
        PrototypeSwingOllamaChunkedRankingAttempt acceptedAttempt = acceptedAttempt(chunk);
        List<String> warnings = warnings(acceptedAttempt);
        PrototypeSwingOllamaChunkedRankingFinalist topFinalist = topFinalist(chunk);
        int chunkIntelligence = clamp((int) Math.round(
                (("CHUNK_FAILED".equals(chunk.chunkStatus()) ? 0 : 100) * 0.20d)
                        + ((acceptedAttempt != null && acceptedAttempt.responseSchemaValid()
                        && acceptedAttempt.responseValidationFailures().isEmpty() ? 100 : 0) * 0.20d)
                        + (statusScore(acceptedAttempt == null ? null : acceptedAttempt.scoreCalibrationStatus()) * 0.20d)
                        + (statusScore(acceptedAttempt == null ? null : acceptedAttempt.rankingQualityStatus()) * 0.25d)
                        + (topFinalist == null ? 0 : finalistQualityScore(topFinalist)) * 0.15d));
        return new PrototypeSwingOllamaIntelligenceScorecardChunk(
                chunk.chunkNumber(),
                chunk.chunkStatus(),
                chunk.candidateCount(),
                chunk.attemptCount(),
                chunk.acceptedAttemptNumber(),
                acceptedAttempt == null ? "NO_ACCEPTED_ATTEMPT" : acceptedAttempt.rankingQualityStatus(),
                acceptedAttempt == null ? "NO_ACCEPTED_ATTEMPT" : acceptedAttempt.scoreCalibrationStatus(),
                acceptedAttempt != null && acceptedAttempt.responseSchemaValid(),
                chunkIntelligence,
                topFinalist == null ? "" : topFinalist.symbol(),
                topFinalist == null ? 0 : topFinalist.chunkActualRank(),
                chunk.finalists() == null ? 0 : chunk.finalists().size(),
                warnings);
    }

    private PrototypeSwingOllamaChunkedRankingAttempt acceptedAttempt(
            PrototypeSwingOllamaChunkedRankingChunk chunk
    ) {
        if (chunk.attempts() == null) {
            return null;
        }
        return chunk.attempts().stream()
                .filter(PrototypeSwingOllamaChunkedRankingAttempt::acceptedForChunkSummary)
                .findFirst()
                .orElse(null);
    }

    private PrototypeSwingOllamaChunkedRankingFinalist topFinalist(
            PrototypeSwingOllamaChunkedRankingChunk chunk
    ) {
        if (chunk.finalists() == null || chunk.finalists().isEmpty()) {
            return null;
        }
        return chunk.finalists().stream()
                .min(Comparator
                        .comparingInt(PrototypeSwingOllamaChunkedRankingFinalist::chunkFinalReviewRank)
                        .thenComparing(PrototypeSwingOllamaChunkedRankingFinalist::symbol))
                .orElse(null);
    }

    private List<String> warnings(PrototypeSwingOllamaChunkedRankingAttempt attempt) {
        List<String> warnings = new ArrayList<>();
        if (attempt == null) {
            warnings.add("NO_ACCEPTED_ATTEMPT");
            return warnings;
        }
        attempt.responseValidationFailures().forEach(failure -> warnings.add("VALIDATION:" + failure));
        attempt.responseNormalizationWarnings().forEach(warning -> warnings.add("NORMALIZATION:" + warning));
        attempt.evaluationFailures().forEach(failure -> warnings.add("EVALUATION:" + failure));
        attempt.calibrationFailures().forEach(failure -> warnings.add("CALIBRATION:" + failure));
        return warnings.stream().distinct().toList();
    }

    private int statusScore(String status) {
        if ("QUALITY_REVIEW_PASSED".equals(status) || "SCORE_CALIBRATION_PASSED".equals(status)) {
            return 100;
        }
        if ("QUALITY_REVIEW_WITH_WARNINGS".equals(status)
                || "SCORE_CALIBRATION_WITH_WARNINGS".equals(status)) {
            return 75;
        }
        if ("QUALITY_REVIEW_WEAK".equals(status) || "SCORE_CALIBRATION_WEAK".equals(status)) {
            return 45;
        }
        return 0;
    }

    private int finalistQualityScore(PrototypeSwingOllamaIntelligenceScorecardChunk chunk) {
        if (chunk.topFinalistActualRank() <= 0) {
            return 0;
        }
        int score = switch (chunk.topFinalistActualRank()) {
            case 1 -> 100;
            case 2 -> 85;
            default -> chunk.topFinalistActualRank() <= Math.max(2, chunk.candidateCount() / 2) ? 65 : 35;
        };
        if (chunk.warnings().stream().anyMatch("EVALUATION:NEGATIVE_RETURN_IN_OLLAMA_TOP_THREE"::equals)) {
            score -= 20;
        }
        if (chunk.warnings().stream().anyMatch("EVALUATION:TOP_PICK_NOT_IN_ACTUAL_TOP_HALF"::equals)) {
            score -= 20;
        }
        return clamp(score);
    }

    private int finalistQualityScore(PrototypeSwingOllamaChunkedRankingFinalist topFinalist) {
        int score = switch (topFinalist.chunkActualRank()) {
            case 1 -> 100;
            case 2 -> 85;
            default -> topFinalist.chunkActualRank() <= 3 ? 65 : 35;
        };
        BigDecimal targetNetReturn = topFinalist.targetNetReturnPercent();
        if (targetNetReturn != null && targetNetReturn.signum() < 0) {
            score -= 20;
        }
        return clamp(score);
    }

    private PrototypeSwingOllamaIntelligenceScorecardDimension dimension(
            String name,
            int score,
            String evidence
    ) {
        return new PrototypeSwingOllamaIntelligenceScorecardDimension(
                name,
                score,
                dimensionStatus(score),
                List.of(evidence));
    }

    private List<String> topImprovementActions(
            PrototypeSwingOllamaChunkedRankingPreview preview,
            int calibration,
            int ranking,
            int finalistQuality,
            int cleanPass,
            int negativeReturnTopPickCount,
            int weakTopPickCount
    ) {
        List<String> actions = new ArrayList<>();
        if (preview.failedChunkCount() > 0) {
            actions.add("Fix failed chunks before expanding evaluation.");
        }
        if (ranking < 80 || weakTopPickCount > 0) {
            actions.add("Add pairwise ranking and top-pick trap examples for weak chunks.");
        }
        if (calibration < 80) {
            actions.add("Strengthen score calibration examples: best actual must receive adequate score spread.");
        }
        if (negativeReturnTopPickCount > 0) {
            actions.add("Add negative-return top-three penalty examples and benchmark-laggard traps.");
        }
        if (finalistQuality < 80) {
            actions.add("Add rotating random and difficult-scenario batches to avoid benchmark overfitting.");
        }
        if (cleanPass < 80) {
            actions.add("Reduce warning chunks before declaring Granite ranking quality stable.");
        }
        if (actions.isEmpty()) {
            actions.add("Proceed to random validation batches and compare against this fixed regression batch.");
        }
        return actions;
    }

    private String status(int score, int failedChunks) {
        if (failedChunks > 0) {
            return "REVIEW_REQUIRED";
        }
        if (score >= 90) {
            return "READY_FOR_BROAD_VALIDATION";
        }
        if (score >= 85) {
            return "READY_FOR_RANDOM_VALIDATION";
        }
        if (score >= 75) {
            return "IMPROVING_NEEDS_RANDOM_VALIDATION";
        }
        return "QUALITY_REVIEW_REQUIRED";
    }

    private String maturityBand(int score, int failedChunks) {
        if (failedChunks > 0) {
            return "PIPELINE_NOT_STABLE";
        }
        if (score >= 90) {
            return "HIGH_CONFIDENCE_REVIEW";
        }
        if (score >= 85) {
            return "RANDOM_VALIDATION_READY";
        }
        if (score >= 75) {
            return "STABLE_PIPELINE_SMARTER_MODEL_NEEDED";
        }
        return "EARLY_INTELLIGENCE_CALIBRATION";
    }

    private String dimensionStatus(int score) {
        if (score >= 90) {
            return "STRONG";
        }
        if (score >= 80) {
            return "GOOD";
        }
        if (score >= 70) {
            return "WATCH";
        }
        return "NEEDS_WORK";
    }

    private int percent(int numerator, int denominator) {
        if (denominator <= 0) {
            return 0;
        }
        return clamp((int) Math.round((numerator * 100.0d) / denominator));
    }

    private int average(int[] values) {
        if (values.length == 0) {
            return 0;
        }
        int total = 0;
        for (int value : values) {
            total += value;
        }
        return clamp((int) Math.round(total / (double) values.length));
    }

    private int clamp(int value) {
        return Math.max(0, Math.min(100, value));
    }
}
