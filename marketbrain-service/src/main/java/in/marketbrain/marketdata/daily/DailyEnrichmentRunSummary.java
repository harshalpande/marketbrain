package in.marketbrain.marketdata.daily;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

public record DailyEnrichmentRunSummary(
        UUID runId,
        String status,
        UUID universeSnapshotId,
        LocalDate requestedFrom,
        LocalDate targetDate,
        String manifestHash,
        int instruments,
        int totalChunks,
        int pendingChunks,
        int runningChunks,
        int retryChunks,
        int completedChunks,
        int failedChunks,
        long acceptedRows,
        long rejectedRows,
        double progressPercent,
        int connectivityFailureCount,
        Instant connectivityRetryAt,
        String lastConnectivityErrorCode,
        boolean workerEnabled,
        boolean schedulerEnabled,
        String detail
) {
}
