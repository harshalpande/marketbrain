package in.marketbrain.marketdata.backfill;

import java.util.UUID;

public record BackfillRetryResult(
        UUID jobId,
        int retriedChunks,
        String status,
        String detail
) {
}
