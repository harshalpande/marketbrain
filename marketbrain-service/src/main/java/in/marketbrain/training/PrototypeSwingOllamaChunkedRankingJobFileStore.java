package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.UUID;

@Component
public class PrototypeSwingOllamaChunkedRankingJobFileStore {

    private final ObjectMapper objectMapper;
    private final Path rootDirectory;

    public PrototypeSwingOllamaChunkedRankingJobFileStore(
            ObjectMapper objectMapper,
            @Value("${marketbrain.review.output-directory:/marketbrain-review}") String outputDirectory
    ) {
        this.objectMapper = objectMapper;
        this.rootDirectory = Path.of(outputDirectory).toAbsolutePath().normalize()
                .resolve("step70-ollama-jobs");
    }

    public String jobDirectory(UUID jobId) {
        return jobDirectoryPath(jobId).toString();
    }

    public void writeRequest(UUID jobId, PrototypeSwingOllamaChunkedRankingRequest request) {
        writeJson(jobId, jobDirectoryPath(jobId).resolve("request.json"), request);
    }

    public void writeStatus(PrototypeSwingOllamaChunkedRankingJobStatus status) {
        writeJson(status.jobId(), jobDirectoryPath(status.jobId()).resolve("status.json"), status);
    }

    public PrototypeSwingOllamaChunkedRankingJobStatus readStatus(UUID jobId) {
        Path statusPath = jobDirectoryPath(jobId).resolve("status.json");
        if (!Files.isRegularFile(statusPath)) {
            throw new IllegalArgumentException("Unknown Ollama ranking jobId.");
        }
        try {
            return objectMapper.readValue(statusPath.toFile(), PrototypeSwingOllamaChunkedRankingJobStatus.class);
        } catch (IOException exception) {
            throw new IllegalStateException("Could not read persisted Ollama ranking job status.", exception);
        }
    }

    public void writeAttempt(UUID jobId, PrototypeSwingOllamaChunkedRankingAttempt attempt) {
        Path attemptsDirectory = jobDirectoryPath(jobId).resolve("attempts");
        String stem = "chunk-%03d-attempt-%02d".formatted(attempt.chunkNumber(), attempt.attemptNumber());
        writeText(jobId, attemptsDirectory.resolve(stem + "-prompt.txt"), attempt.prompt());
        writeText(jobId, attemptsDirectory.resolve(stem + "-ollama-response.json"), attempt.ollamaResponse());
        writeJson(jobId, attemptsDirectory.resolve(stem + "-attempt.json"), attempt);
    }

    public void writeChunk(UUID jobId, PrototypeSwingOllamaChunkedRankingChunk chunk) {
        Path chunksDirectory = jobDirectoryPath(jobId).resolve("chunks");
        writeJson(jobId, chunksDirectory.resolve("chunk-%03d.json".formatted(chunk.chunkNumber())), chunk);
    }

    public void writeResult(UUID jobId, PrototypeSwingOllamaChunkedRankingPreview result) {
        writeJson(jobId, jobDirectoryPath(jobId).resolve("result.json"), result);
    }

    public void writeFailure(UUID jobId, RuntimeException exception) {
        writeJson(jobId, jobDirectoryPath(jobId).resolve("failure.json"),
                new PersistedFailure(
                        jobId,
                        Instant.now(),
                        exception.getClass().getName(),
                        exception.getMessage()));
    }

    private Path jobDirectoryPath(UUID jobId) {
        return rootDirectory.resolve(jobId.toString()).normalize();
    }

    private void writeJson(UUID jobId, Path path, Object value) {
        try {
            Files.createDirectories(path.getParent());
            Path temporaryPath = temporaryPath(path);
            objectMapper.writerWithDefaultPrettyPrinter().writeValue(temporaryPath.toFile(), value);
            Files.move(temporaryPath, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException exception) {
            throw new IllegalStateException("Could not persist Ollama ranking job evidence for " + jobId + ".", exception);
        }
    }

    private void writeText(UUID jobId, Path path, String value) {
        try {
            Files.createDirectories(path.getParent());
            Path temporaryPath = temporaryPath(path);
            Files.writeString(temporaryPath, value == null ? "" : value, StandardCharsets.UTF_8);
            Files.move(temporaryPath, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException exception) {
            throw new IllegalStateException("Could not persist Ollama ranking job text evidence for " + jobId + ".", exception);
        }
    }

    private Path temporaryPath(Path path) {
        return path.resolveSibling(path.getFileName() + ".tmp");
    }

    private record PersistedFailure(
            UUID jobId,
            Instant observedAt,
            String exceptionType,
            String message
    ) {
    }
}
