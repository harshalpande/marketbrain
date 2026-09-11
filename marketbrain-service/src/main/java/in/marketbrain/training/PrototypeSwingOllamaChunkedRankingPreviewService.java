package in.marketbrain.training;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

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

    @Transactional(readOnly = true, timeout = 2400)
    public PrototypeSwingOllamaChunkedRankingPreview preview(
            PrototypeSwingOllamaChunkedRankingRequest request
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
        for (int offset = startOffset; offset < stopOffsetExclusive; offset += chunkSize) {
            int chunkNumber = (offset / chunkSize) + 1;
            int requestedChunkSize = Math.min(chunkSize, stopOffsetExclusive - offset);
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

        for (int attemptNumber = 1; attemptNumber <= maxRetriesPerChunk + 1; attemptNumber++) {
            PrototypeSwingOllamaRankingRequest rankingRequest =
                    new PrototypeSwingOllamaRankingRequest(runId, model, candidates.size(), horizon);
            PrototypeSwingOllamaGuidedRankingPreview guided =
                    guidedRankingService.previewCandidates(rankingRequest, candidates);
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation =
                    evaluationService.evaluateGuidedPreview(guided);
            PrototypeSwingOllamaScoreCalibrationBatch calibration =
                    calibrationService.batch(candidates.size(), evaluation);
            boolean accepted = chunkAccepted(calibration);
            attempts.add(attempt(
                    chunkNumber,
                    attemptNumber,
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
            List<PrototypeSwingOllamaCandidate> candidates,
            PrototypeSwingOllamaGuidedRankingEvaluationPreview evaluation,
            PrototypeSwingOllamaScoreCalibrationBatch calibration,
            boolean accepted
    ) {
        return new PrototypeSwingOllamaChunkedRankingAttempt(
                chunkNumber,
                attemptNumber,
                candidateIds(candidates),
                symbols(candidates),
                evaluation.responseHash(),
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

    private List<String> candidateIds(List<PrototypeSwingOllamaCandidate> candidates) {
        List<String> result = new ArrayList<>();
        for (int index = 0; index < candidates.size(); index++) {
            result.add(PrototypeSwingOllamaGuidedRankingPreviewService.candidateId(index));
        }
        return result;
    }

    private boolean chunkAccepted(PrototypeSwingOllamaScoreCalibrationBatch calibration) {
        return calibration.responseSchemaValid()
                && !"SCORE_CALIBRATION_BLOCKED".equals(calibration.scoreCalibrationStatus());
    }

    private List<PrototypeSwingOllamaChunkedRankingFinalist> finalists(
            PrototypeSwingOllamaScoreCalibrationBatch calibration,
            int chunkNumber,
            int finalistsPerChunk
    ) {
        return calibration.evaluationPreview().candidateEvaluations().stream()
                .sorted(Comparator
                        .comparingInt(PrototypeSwingOllamaCandidateEvaluation::ollamaRank)
                        .thenComparing(PrototypeSwingOllamaCandidateEvaluation::symbol))
                .limit(finalistsPerChunk)
                .map(row -> new PrototypeSwingOllamaChunkedRankingFinalist(
                        chunkNumber,
                        row.symbol(),
                        row.ollamaRank(),
                        row.actualRank(),
                        row.ollamaScore(),
                        row.ollamaConfidence(),
                        row.targetNetReturnPercent(),
                        row.targetBenchmarkExcessReturnPercent(),
                        row.targetMaximumDrawdownPercent(),
                        row.qualityBucket(),
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
        if (trimmed.length() > 80 || !trimmed.matches("^[A-Za-z0-9._:-]+$")) {
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
}
