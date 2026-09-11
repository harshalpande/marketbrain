package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record PrototypeSwingOllamaScoreCalibrationPreview(
        String status,
        UUID datasetRunId,
        String model,
        LocalDate asOf,
        LocalDate labelThrough,
        int rankingHorizonSessions,
        String calibrationVersion,
        List<Integer> candidateLimits,
        int batchCount,
        int schemaValidBatchCount,
        int calibrationPassedBatchCount,
        int calibrationWarningBatchCount,
        int calibrationWeakBatchCount,
        int ollamaCallCount,
        List<String> aggregateFailures,
        List<PrototypeSwingOllamaScoreCalibrationBatch> batches,
        boolean databaseWritesPerformed,
        int signalsCreated,
        int ordersCreated,
        boolean actionExecutionEnabled,
        String detail
) {
}
