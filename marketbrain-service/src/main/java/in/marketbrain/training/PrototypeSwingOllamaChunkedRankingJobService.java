package in.marketbrain.training;

import jakarta.annotation.PreDestroy;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@Service
public class PrototypeSwingOllamaChunkedRankingJobService {

    private final PrototypeSwingOllamaChunkedRankingPreviewService previewService;
    private final ExecutorService executor = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "marketbrain-ollama-ranking-worker");
        thread.setDaemon(true);
        return thread;
    });
    private final Map<UUID, JobState> jobs = new ConcurrentHashMap<>();

    public PrototypeSwingOllamaChunkedRankingJobService(
            PrototypeSwingOllamaChunkedRankingPreviewService previewService
    ) {
        this.previewService = previewService;
    }

    public PrototypeSwingOllamaChunkedRankingJobStatus submit(PrototypeSwingOllamaChunkedRankingRequest request) {
        UUID jobId = UUID.randomUUID();
        JobState state = new JobState(jobId, request, Instant.now());
        jobs.put(jobId, state);
        executor.submit(() -> run(state));
        return state.status();
    }

    public PrototypeSwingOllamaChunkedRankingJobStatus status(UUID jobId) {
        JobState state = jobs.get(jobId);
        if (state == null) {
            throw new IllegalArgumentException("Unknown Ollama ranking jobId.");
        }
        return state.status();
    }

    private void run(JobState state) {
        state.startedAt = Instant.now();
        state.status = "RUNNING";
        state.detail = "Ollama ranking job started with Java-side async orchestration and model concurrency fixed at 1.";
        try {
            PrototypeSwingOllamaChunkedRankingPreview result = previewService.preview(
                    state.request,
                    progress -> {
                        state.activeChunkNumber = progress.activeChunkNumber();
                        state.targetChunkCount = progress.targetChunkCount();
                        state.completedChunkCount = progress.completedChunkCount();
                        state.passedChunkCount = progress.passedChunkCount();
                        state.failedChunkCount = progress.failedChunkCount();
                        state.progressPercent = progress.progressPercent();
                        state.detail = progress.detail();
                    });
            state.result = result;
            state.model = result.model();
            state.progressPercent = 100;
            state.completedChunkCount = result.chunkCount();
            state.passedChunkCount = result.passedChunkCount();
            state.failedChunkCount = result.failedChunkCount();
            state.targetChunkCount = result.chunkCount();
            state.status = "COMPLETED";
            state.detail = "Ollama ranking job completed. Review result, root causes, and guardrail statuses before using any finding.";
        } catch (RuntimeException exception) {
            state.status = "FAILED";
            state.errorMessage = exception.getMessage();
            state.detail = "Ollama ranking job failed safely. No database write, signal, order, or broker action was created.";
        } finally {
            state.completedAt = Instant.now();
        }
    }

    @PreDestroy
    void shutdown() {
        executor.shutdownNow();
    }

    private static final class JobState {
        private final UUID jobId;
        private final PrototypeSwingOllamaChunkedRankingRequest request;
        private final Instant submittedAt;
        private volatile String status = "QUEUED";
        private volatile int progressPercent;
        private volatile int activeChunkNumber;
        private volatile int targetChunkCount;
        private volatile int completedChunkCount;
        private volatile int passedChunkCount;
        private volatile int failedChunkCount;
        private volatile String model;
        private volatile Instant startedAt;
        private volatile Instant completedAt;
        private volatile String errorMessage;
        private volatile PrototypeSwingOllamaChunkedRankingPreview result;
        private volatile String detail = "Queued for the single local Ollama worker. Model concurrency is intentionally 1.";

        private JobState(
                UUID jobId,
                PrototypeSwingOllamaChunkedRankingRequest request,
                Instant submittedAt
        ) {
            this.jobId = jobId;
            this.request = request;
            this.submittedAt = submittedAt;
            this.model = request == null ? null : request.model();
        }

        private PrototypeSwingOllamaChunkedRankingJobStatus status() {
            return new PrototypeSwingOllamaChunkedRankingJobStatus(
                    jobId,
                    status,
                    progressPercent,
                    activeChunkNumber,
                    targetChunkCount,
                    completedChunkCount,
                    passedChunkCount,
                    failedChunkCount,
                    model,
                    submittedAt,
                    startedAt,
                    completedAt,
                    errorMessage,
                    result,
                    false,
                    0,
                    0,
                    false,
                    detail
            );
        }
    }
}
