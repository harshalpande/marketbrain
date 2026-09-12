package in.marketbrain.training;

import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;

@Service
public class PrototypeSwingOllamaChunkedRankingPreviewService {

    static final String CHUNKED_RANKING_VERSION = "MARKETBRAIN_OLLAMA_CHUNKED_RANKING_V1";

    private static final int DEFAULT_TOTAL_CANDIDATE_LIMIT = 12;
    private static final int DEFAULT_CHUNK_SIZE = 4;
    private static final int DEFAULT_FINALISTS_PER_CHUNK = 2;
    private static final int DEFAULT_MAX_RETRIES_PER_CHUNK = 1;
    private static final int DEFAULT_RANKING_HORIZON_SESSIONS = 20;

    private final PrototypeSwingTrainingDatasetAuditService auditService;
    private final PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService;
    private final PrototypeSwingOllamaGuidedRankingEvaluationPreviewService evaluationService;
    private final PrototypeSwingOllamaScoreCalibrationPreviewService calibrationService;

    public PrototypeSwingOllamaChunkedRankingPreviewService(
            PrototypeSwingTrainingDatasetAuditService auditService,
            PrototypeSwingOllamaGuidedRankingPreviewService guidedRankingService,
            PrototypeSwingOllamaGuidedRankingEvaluationPreviewService evaluationService,
            PrototypeSwingOllamaScoreCalibrationPreviewService calibrationService
    ) {
        this.auditService = auditService;
        this.guidedRankingService = guidedRankingService;
        this.evaluationService = evaluationService;
        this.calibrationService = calibrationService;
    }
    public PrototypeSwingOllamaChunkedRankingPreview preview(
            PrototypeSwingOllamaChunkedRankingRequest request
    ) {
        return preview(request, progress -> {
        });
    }
    public PrototypeSwingOllamaChunkedRankingPreview preview(
            PrototypeSwingOllamaChunkedRankingRequest request,
            Consumer<ChunkProgress> progressConsumer
    ) {
        PrototypeSwingOllamaChunkedRankingRequest safeRequest = request == null
                ? new PrototypeSwingOllamaChunkedRankingRequest(null, null, null, null, null, null, null, null)
                : request;
        String model = model(safeRequest.model());
        int startOffset = startOffset(safeRequest.startOffset());
        int totalCandidateLimit = totalCandidateLimit(safeRequest.totalCandidateLimit());
        int chunkSize = chunkSize(safeRequest.chunkSize());
        int finalistsPerChunk = finalistsPerChunk(safeRequest.finalistsPerChunk(), chunkSize);
        int maxRetriesPerChunk = maxRetriesPerChunk(safeRequest.maxRetriesPerChunk());
        int horizon = horizon(safeRequest.rankingHorizonSessions());
        PrototypeSwingTrainingDatasetAudit audit = auditService.audit(safeRequest.datasetRunId());
        UUID runId = audit.datasetRunId();

        List<PrototypeSwingOllamaChunkedRankingChunk> chunks = new ArrayList<>();
        List<PrototypeSwingOllamaChunkedRankingFinalist> mergedFinalists = new ArrayList<>();
        List<String> aggregateFailures = new ArrayList<>();
        int processedCandidateCount = 0;
        int ollamaCallCount = 0;

        int stopOffsetExclusive = startOffset + totalCandidateLimit;
        int targetChunkCount = (int) Math.ceil(totalCandidateLimit / (double) chunkSize);
        for (int offset = startOffset; offset < stopOffsetExclusive; offset += chunkSize) {
            int chunkNumber = (offset / chunkSize) + 1;
            int requestedChunkSize = Math.min(chunkSize, stopOffsetExclusive - offset);
            progressConsumer.accept(new ChunkProgress(
                    "RUNNING",
                    chunkNumber,
                    targetChunkCount,
                    chunks.size(),
                    0,
                    0,
                    "Starting chunk " + chunkNumber + " of " + targetChunkCount
            ));
            List<PrototypeSwingOllamaCandidate> candidates =
                    guidedRankingService.candidates(runId, offset, requestedChunkSize);
            if (candidates.isEmpty()) {
                break;
            }
            processedCandidateCount += candidates.size();
            ChunkRun chunkRun = runChunk(
                    runId,
                    model,
                    horizon,
                    chunkNumber,
                    offset,
                    candidates,
                    finalistsPerChunk,
                    maxRetriesPerChunk
            );
            ollamaCallCount += chunkRun.chunk().attemptCount();
            chunks.add(chunkRun.chunk());
            mergedFinalists.addAll(chunkRun.chunk().finalists());
            aggregateFailures.addAll(chunkRun.failures());
            int passedSoFar = (int) chunks.stream()
                    .filter(chunk -> "CHUNK_PASSED".equals(chunk.chunkStatus()))
                    .count();
            int failedSoFar = (int) chunks.stream()
                    .filter(chunk -> "CHUNK_FAILED".equals(chunk.chunkStatus()))
                    .count();
            progressConsumer.accept(new ChunkProgress(
                    "RUNNING",
                    chunkNumber,
                    targetChunkCount,
                    chunks.size(),
                    passedSoFar,
                    failedSoFar,
                    "Completed chunk " + chunkNumber + " with status " + chunkRun.chunk().chunkStatus()
            ));
        }

        mergedFinalists.sort(Comparator
                .comparingInt(PrototypeSwingOllamaChunkedRankingFinalist::ollamaScore)
                .reversed()
                .thenComparing(PrototypeSwingOllamaChunkedRankingFinalist::symbol));

        int failedChunkCount = (int) chunks.stream()
                .filter(chunk -> "CHUNK_FAILED".equals(chunk.chunkStatus()))
                .count();
        int warningChunkCount = (int) chunks.stream()
                .filter(chunk -> "CHUNK_ACCEPTED_WITH_WARNINGS".equals(chunk.chunkStatus()))
                .count();
        int passedChunkCount = (int) chunks.stream()
                .filter(chunk -> "CHUNK_PASSED".equals(chunk.chunkStatus()))
                .count();

        return new PrototypeSwingOllamaChunkedRankingPreview(
                failedChunkCount == 0 && aggregateFailures.isEmpty() ? "REVIEW_REQUIRED" : "REVIEW_WITH_WARNINGS",
                runId,
                model,
                audit.asOf(),
                audit.labelThrough(),
                startOffset,
                totalCandidateLimit,
                chunkSize,
                finalistsPerChunk,
                maxRetriesPerChunk,
                horizon,
                CHUNKED_RANKING_VERSION,
                chunks.size(),
                passedChunkCount,
                warningChunkCount,
                failedChunkCount,
                processedCandidateCount,
                mergedFinalists.size(),
                ollamaCallCount,
                List.copyOf(chunks),
                List.copyOf(mergedFinalists),
                List.copyOf(new LinkedHashSet<>(aggregateFailures)),
                false,
                0,
                0,
                false,
                "Step 70 processed candidates in small calibrated chunks. Each chunk was guarded, evaluated, "
                        + "optionally retried, and summarized without creating a signal, paper fill, order, "
                        + "broker action, or live trading action."
        );
    }

    private ChunkRun runChunk(
            UUID runId,
            String model,
            int horizon,
            int chunkNumber,
            int offset,
            List<PrototypeSwingOllamaCandidate> candidates,
            int finalistsPerChunk,
            int maxRetriesPerChunk
    ) {
        List<PrototypeSwingOllamaChunkedRankingAttempt> attempts = new ArrayList<>();
        List<String> failures = new ArrayList<>();
        PrototypeSwingOllamaScoreCalibrationBatch acceptedBatch = null;
        int acceptedAttemptNumber = 0;
        String repairInstruction = null;

        for (int attemptNumber = 1; attemptNumber <= maxRetriesPerChunk + 1; attemptNumber++) {
            PrototypeSwingOllamaRankingRequest rankingRequest =
                    new PrototypeSwingOllamaRankingRequest(
                            runId,
                            model,
                            candidates.size(),
                            horizon,
                            repairInstruction);
            PrototypeSwingOllamaGuidedRankingPreview guided =
                    guidedRankingService.previewCandidates(rankingRequest, candidates);
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation =
                    evaluationService.evaluateGuidedPreview(guided);
            PrototypeSwingOllamaScoreCalibrationBatch calibration =
                    calibrationService.batch(candidates.size(), evaluation);
            boolean lastAttempt = attemptNumber == maxRetriesPerChunk + 1;
            boolean accepted = chunkAccepted(calibration, lastAttempt);
            attempts.add(attempt(
                    chunkNumber,
                    attemptNumber,
                    repairInstruction,
                    candidates,
                    evaluation,
                    calibration,
                    accepted
            ));
            if (accepted) {
                acceptedBatch = calibration;
                acceptedAttemptNumber = attemptNumber;
                break;
            }
            repairInstruction = repairInstruction(candidates, evaluation, calibration);
        }

        String chunkStatus;
        List<PrototypeSwingOllamaChunkedRankingFinalist> finalists = List.of();
        if (acceptedBatch == null) {
            chunkStatus = "CHUNK_FAILED";
            failures.add("CHUNK_" + chunkNumber + "_FAILED_AFTER_RETRIES");
        } else if ("SCORE_CALIBRATION_PASSED".equals(acceptedBatch.scoreCalibrationStatus())
                && acceptedBatch.evaluationPreview().evaluationFailures().isEmpty()) {
            chunkStatus = "CHUNK_PASSED";
            finalists = finalists(acceptedBatch, chunkNumber, finalistsPerChunk);
        } else {
            chunkStatus = "CHUNK_ACCEPTED_WITH_WARNINGS";
            finalists = finalists(acceptedBatch, chunkNumber, finalistsPerChunk);
            failures.add("CHUNK_" + chunkNumber + "_ACCEPTED_WITH_WARNINGS");
        }

        return new ChunkRun(new PrototypeSwingOllamaChunkedRankingChunk(
                chunkNumber,
                offset,
                candidates.size(),
                symbols(candidates),
                chunkStatus,
                attempts.size(),
                acceptedAttemptNumber,
                List.copyOf(attempts),
                finalists,
                acceptedBatch
        ), failures);
    }

    private PrototypeSwingOllamaChunkedRankingAttempt attempt(
            int chunkNumber,
            int attemptNumber,
            String repairInstruction,
            List<PrototypeSwingOllamaCandidate> candidates,
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation,
            PrototypeSwingOllamaScoreCalibrationBatch calibration,
            boolean accepted
    ) {
        return new PrototypeSwingOllamaChunkedRankingAttempt(
                chunkNumber,
                attemptNumber,
                repairInstruction,
                candidateIds(candidates),
                symbols(candidates),
                evaluation.guidedPreview().promptHash(),
                evaluation.guidedPreview().prompt(),
                evaluation.guidedPreview().promptCharacterCount(),
                evaluation.responseHash(),
                evaluation.guidedPreview().responseCharacterCount(),
                evaluation.guidedPreview().ollamaElapsedMillis(),
                evaluation.guidedPreview().ollamaTotalDurationNanos(),
                evaluation.guidedPreview().ollamaPromptEvalCount(),
                evaluation.guidedPreview().ollamaEvalCount(),
                evaluation.guidedPreview().ollamaResponse(),
                evaluation.responseParseableJson(),
                evaluation.responseSchemaValid(),
                evaluation.rankingQualityStatus(),
                calibration.scoreCalibrationStatus(),
                evaluation.responseValidationFailures(),
                evaluation.evaluationFailures(),
                calibration.calibrationFailures(),
                accepted
        );
    }

    private String repairInstruction(
            List<PrototypeSwingOllamaCandidate> candidates,
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation,
            PrototypeSwingOllamaScoreCalibrationBatch calibration
    ) {
        List<String> failures = new ArrayList<>();
        failures.addAll(evaluation.responseValidationFailures());
        failures.addAll(evaluation.evaluationFailures());
        failures.addAll(calibration.calibrationFailures());

        StringBuilder builder = new StringBuilder();
        builder.append("Your previous response failed MarketBrain guardrails. ");
        builder.append("Return a corrected JSON object only. ");
        builder.append("The rankedCandidates array must contain exactly ")
                .append(candidates.size())
                .append(" objects, no more and no fewer. ");
        builder.append("Use these exact candidateId/symbol pairs exactly once: ");
        for (int index = 0; index < candidates.size(); index++) {
            if (index > 0) {
                builder.append("; ");
            }
            builder.append(PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index))
                    .append("=")
                    .append(candidates.get(index).symbol());
        }
        builder.append(". Ranks must be the complete sequence 1..")
                .append(candidates.size())
                .append(". ");
        if (!failures.isEmpty()) {
            builder.append("Previous guardrail failures: ")
                    .append(String.join(", ", new LinkedHashSet<>(failures)))
                    .append(". ");
        }
        if (failures.contains("RANKED_CANDIDATE_COUNT")) {
            builder.append("Specifically fix RANKED_CANDIDATE_COUNT by returning one rankedCandidates row for every listed candidateId. ");
        }
        if (failures.contains("TOP_PICK_NOT_IN_ACTUAL_TOP_HALF")
                || failures.contains("TOP_SCORE_NOT_ACTUAL_TOP_HALF")
                || failures.contains("NEGATIVE_RANK_CORRELATION")
                || failures.contains("NEGATIVE_SCORE_RANK_CORRELATION")) {
            builder.append("Reconsider the full ordering; the previous top/score ordering was directionally weak. ");
            builder.append("Do not over-rank a candidate just because one metric looks attractive. ");
        }
        if (failures.contains("HIGH_CONFIDENCE_MISS")
                || failures.contains("HIGH_SCORE_BOTTOM_HALF_MISS")
                || failures.contains("HIGH_CONFIDENCE_TOP_SCORE_MISS")
                || failures.contains("HIGH_CONFIDENCE_BOTTOM_HALF_MISS")) {
            builder.append("Recalibrate confidence: HIGH is forbidden for conflicted candidates and should be rare. ");
            builder.append("Use MEDIUM/LOW when risk flags or caveats are meaningful. ");
        }
        if (failures.contains("TOP_SCORE_NEGATIVE_RETURN")
                || failures.contains("HIGH_SCORE_NEGATIVE_RETURN")
                || failures.contains("NEGATIVE_RETURN_IN_OLLAMA_TOP_THREE")) {
            builder.append("Demote negative-return or likely-laggard profiles; they must not receive top-three rank, HIGH confidence, or 85+ score. ");
        }
        if (failures.contains("BEST_ACTUAL_SCORE_TOO_LOW")) {
            builder.append("Use a wider score scale and make the strongest relative setup in this chunk score at least 70 unless every candidate is poor. ");
        }
        if (failures.stream().anyMatch(failure -> failure.startsWith("SIGNED_CONTRIBUTION"))
                || failures.contains("SIGNED_CONTRIBUTIONS_OBJECT")) {
            builder.append("Every ranked candidate must include signedContributions with trendContribution, momentumContribution, participationContribution, riskPenalty, recoveryCredit, overextensionPenalty, algorithmAdjustment and finalScore. ");
            builder.append("All signed contribution fields except finalScore must be integers from -100 to 100. ");
            builder.append("riskPenalty and overextensionPenalty should normally be zero or negative because they reduce score. ");
            builder.append("finalScore must be 0 to 100 and within 10 points of score. ");
        }
        builder.append("Apply the score_cap_hint rules in the prompt. ");
        builder.append("Do not drop lower-ranked candidates. Do not add symbols outside this list. Do not use markdown.");
        return builder.toString();
    }

    private List<String> candidateIds(List<PrototypeSwingOllamaCandidate> candidates) {
        List<String> result = new ArrayList<>();
        for (int index = 0; index < candidates.size(); index++) {
            result.add(PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index));
        }
        return result;
    }

    private boolean chunkAccepted(
            PrototypeSwingOllamaScoreCalibrationBatch calibration,
            boolean lastAttempt
    ) {
        if (!calibration.responseSchemaValid()
                || "SCORE_CALIBRATION_BLOCKED".equals(calibration.scoreCalibrationStatus())) {
            return false;
        }
        if ("SCORE_CALIBRATION_WEAK".equals(calibration.scoreCalibrationStatus())
                || "QUALITY_REVIEW_WEAK".equals(calibration.rankingQualityStatus())) {
            return lastAttempt;
        }
        return true;
    }

    private List<PrototypeSwingOllamaChunkedRankingFinalist> finalists(
            PrototypeSwingOllamaScoreCalibrationBatch calibration,
            int chunkNumber,
            int finalistsPerChunk
    ) {
        return calibration.evaluationPreview().candidateEvaluations().stream()
                .sorted(Comparator
                        .comparingInt(PrototypeSwingOllamaCandidateEvaluation::finalReviewRank)
                        .thenComparing(PrototypeSwingOllamaCandidateEvaluation::symbol))
                .limit(finalistsPerChunk)
                .map(row -> new PrototypeSwingOllamaChunkedRankingFinalist(
                        chunkNumber,
                        row.symbol(),
                        row.ollamaRank(),
                        row.javaBaselineRank(),
                        row.finalReviewRank(),
                        row.actualRank(),
                        row.ollamaScore(),
                        row.javaBaselineScore(),
                        row.finalReviewScore(),
                        row.ollamaConfidence(),
                        row.arbitrationDecision(),
                        row.targetNetReturnPercent(),
                        row.targetBenchmarkExcessReturnPercent(),
                        row.targetMaximumDrawdownPercent(),
                        row.qualityBucket(),
                        row.javaBaselineReason(),
                        row.arbitrationReason(),
                        row.reason()
                ))
                .toList();
    }

    private List<String> symbols(List<PrototypeSwingOllamaCandidate> candidates) {
        return candidates.stream().map(PrototypeSwingOllamaCandidate::symbol).toList();
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

    private int totalCandidateLimit(Integer value) {
        int limit = value == null ? DEFAULT_TOTAL_CANDIDATE_LIMIT : value;
        if (limit < 1 || limit > 100) {
            throw new IllegalArgumentException("totalCandidateLimit must be between 1 and 100.");
        }
        return limit;
    }

    private int startOffset(Integer value) {
        int offset = value == null ? 0 : value;
        if (offset < 0 || offset > 500) {
            throw new IllegalArgumentException("startOffset must be between 0 and 500.");
        }
        return offset;
    }

    private int chunkSize(Integer value) {
        int size = value == null ? DEFAULT_CHUNK_SIZE : value;
        if (size < 1 || size > 5) {
            throw new IllegalArgumentException("chunkSize must be between 1 and 5.");
        }
        return size;
    }

    private int finalistsPerChunk(Integer value, int chunkSize) {
        int finalists = value == null ? DEFAULT_FINALISTS_PER_CHUNK : value;
        if (finalists < 1 || finalists > chunkSize) {
            throw new IllegalArgumentException("finalistsPerChunk must be between 1 and chunkSize.");
        }
        return finalists;
    }

    private int maxRetriesPerChunk(Integer value) {
        int retries = value == null ? DEFAULT_MAX_RETRIES_PER_CHUNK : value;
        if (retries < 0 || retries > 3) {
            throw new IllegalArgumentException("maxRetriesPerChunk must be between 0 and 3.");
        }
        return retries;
    }

    private int horizon(Integer value) {
        int horizon = value == null ? DEFAULT_RANKING_HORIZON_SESSIONS : value;
        if (!SwingTrainingDatasetPreviewService.HORIZONS.contains(horizon)) {
            throw new IllegalArgumentException("rankingHorizonSessions must be one of 5, 20, or 60.");
        }
        return horizon;
    }

    private record ChunkRun(
            PrototypeSwingOllamaChunkedRankingChunk chunk,
            List<String> failures
    ) {
    }

    public record ChunkProgress(
            String status,
            int activeChunkNumber,
            int targetChunkCount,
            int completedChunkCount,
            int passedChunkCount,
            int failedChunkCount,
            String detail
    ) {
        public int progressPercent() {
            if (targetChunkCount <= 0) {
                return 0;
            }
            return Math.max(0, Math.min(100,
                    (int) Math.floor((completedChunkCount / (double) targetChunkCount) * 100)));
        }
    }
}
