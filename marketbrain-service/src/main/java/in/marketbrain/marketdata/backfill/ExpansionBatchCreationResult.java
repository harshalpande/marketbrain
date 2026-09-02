package in.marketbrain.marketdata.backfill;

public record ExpansionBatchCreationResult(
        BackfillJobSummary job,
        int batchNumber,
        int selectedInstruments,
        int remainingInstrumentsAfterBatch,
        int maximumBatchSize,
        String detail
) {
}
