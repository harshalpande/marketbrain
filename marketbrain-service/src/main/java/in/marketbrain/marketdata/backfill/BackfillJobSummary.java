package in.marketbrain.marketdata.backfill;

import java.time.LocalDate;
import java.time.Instant;
import java.util.UUID;

public record BackfillJobSummary(
        UUID jobId,
        String status,
        LocalDate fromDate,
        LocalDate toDate,
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
        String detail
) {
}
