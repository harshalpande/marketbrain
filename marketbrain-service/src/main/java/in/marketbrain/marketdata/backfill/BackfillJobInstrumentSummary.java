package in.marketbrain.marketdata.backfill;

public record BackfillJobInstrumentSummary(
        String symbol,
        String providerInstrumentKey,
        int totalChunks,
        int pendingChunks,
        int runningChunks,
        int retryChunks,
        int completedChunks,
        int failedChunks
) {
}
