package in.marketbrain.training;

import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaIntelligenceScorecard(
        String status,
        UUID datasetRunId,
        String model,
        String selectionMode,
        int startOffset,
        int totalCandidateLimit,
        int chunkSize,
        int chunkCount,
        int processedCandidateCount,
        int finalistCount,
        int ollamaCallCount,
        int overallIntelligenceScorePercent,
        int pendingImprovementPercent,
        String maturityBand,
        int pipelineReliabilityPercent,
        int cleanPassPercent,
        int schemaDisciplinePercent,
        int scoreCalibrationPercent,
        int rankingQualityPercent,
        int finalistQualityPercent,
        int failedChunkCount,
        int warningChunkCount,
        int passedChunkCount,
        int acceptedWithWarningsCount,
        int negativeReturnTopPickCount,
        int weakTopPickCount,
        List<PrototypeSwingOllamaIntelligenceScorecardDimension> dimensions,
        List<PrototypeSwingOllamaIntelligenceScorecardChunk> chunks,
        List<String> topImprovementActions,
        List<String> guardrails,
        boolean databaseWritesPerformed,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
