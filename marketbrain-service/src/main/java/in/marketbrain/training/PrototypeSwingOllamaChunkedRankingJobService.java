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
    private final PrototypeSwingOllamaChunkedRankingJobFileStore fileStore;
    private final ExecutorService executor = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "marketbrain-ollama-ranking-worker");
        thread.setDaemon(true);
        return thread;
    });
    private final Map<UUID, JobState> jobs = new ConcurrentHashMap<>();

    public PrototypeSwingOllamaChunkedRankingJobService(
            PrototypeSwingOllamaChunkedRankingPreviewService previewService,
            PrototypeSwingOllamaChunkedRankingJobFileStore fileStore
    ) {
        this.previewService = previewService;
        this.fileStore = fileStore;
    }

    public PrototypeSwingOllamaChunkedRankingJobStatus submit(PrototypeSwingOllamaChunkedRankingRequest request) {
        UUID jobId = UUID.randomUUID();
        JobState state = new JobState(jobId, request, Instant.now(), fileStore.jobDirectory(jobId));
        jobs.put(jobId, state);
        fileStore.writeRequest(jobId, request);
        fileStore.writeStatus(state.status());
        executor.submit(() -> run(state));
        return state.status();
    }

    public PrototypeSwingOllamaChunkedRankingJobStatus status(UUID jobId) {
        JobState state = jobs.get(jobId);
        if (state == null) {
            PrototypeSwingOllamaChunkedRankingJobStatus persisted = fileStore.readStatus(jobId);
            if (!"COMPLETED".equals(persisted.status()) && !"FAILED".equals(persisted.status())) {
                PrototypeSwingOllamaChunkedRankingJobStatus recovered = new PrototypeSwingOllamaChunkedRankingJobStatus(
                        persisted.jobId(),
                        "LOST_AFTER_RESTART",
                        persisted.progressPercent(),
                        persisted.activeChunkNumber(),
                        persisted.targetChunkCount(),
                        persisted.completedChunkCount(),
                        persisted.passedChunkCount(),
                        persisted.failedChunkCount(),
                        persisted.model(),
                        persisted.submittedAt(),
                        persisted.startedAt(),
                        Instant.now(),
                        "The Java worker is no longer active. Review persisted evidence and start a fresh run.",
                        persisted.result(),
                        persisted.databaseWritesPerformed(),
                        persisted.signalsCreated(),
                        persisted.ordersCreated(),
                        persisted.actionExecutionEnabled(),
                        "The job evidence was recovered from disk after a service restart, but the in-memory worker was lost.",
                        persisted.evidenceDirectory());
                fileStore.writeStatus(recovered);
                return recovered;
            }
            return persisted;
        }
        return state.status();
    }

    private void run(JobState state) {
        state.startedAt = Instant.now();
        state.status = "RUNNING";
        state.detail = "Ollama ranking job started with Java-side async orchestration and model concurrency fixed at 1.";
        fileStore.writeStatus(state.status());
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
                        fileStore.writeStatus(state.status());
                    },
                    new PrototypeSwingOllamaChunkedRankingPreviewService.ChunkEvidenceConsumer() {
                        @Override
                        public void onAttempt(PrototypeSwingOllamaChunkedRankingAttempt attempt) {
                            fileStore.writeAttempt(state.jobId, attempt);
                            fileStore.writeStatus(state.status());
                        }

                        @Override
                        public void onChunk(PrototypeSwingOllamaChunkedRankingChunk chunk) {
                            fileStore.writeChunk(state.jobId, chunk);
                            fileStore.writeStatus(state.status());
                        }
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
            fileStore.writeResult(state.jobId, result);
            fileStore.writeStatus(state.status());
        } catch (RuntimeException exception) {
            state.status = "FAILED";
            state.errorMessage = exception.getMessage();
            state.detail = "Ollama ranking job failed safely. No database write, signal, order, or broker action was created.";
            fileStore.writeFailure(state.jobId, exception);
            fileStore.writeStatus(state.status());
        } finally {
            state.completedAt = Instant.now();
            fileStore.writeStatus(state.status());
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
        private final String evidenceDirectory;

        private JobState(
                UUID jobId,
                PrototypeSwingOllamaChunkedRankingRequest request,
                Instant submittedAt,
                String evidenceDirectory
        ) {
            this.jobId = jobId;
            this.request = request;
            this.submittedAt = submittedAt;
            this.model = request == null ? null : request.model();
            this.evidenceDirectory = evidenceDirectory;
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
                    detail,
                    evidenceDirectory
            );
        }
    }
}
