package in.marketbrain.marketdata.backfill;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record ExpansionBatchPreview(
        UUID snapshotId,
        int batchNumber,
        int years,
        LocalDate requestedFrom,
        LocalDate requestedTo,
        int selectedInstruments,
        int remainingInstrumentsAfterBatch,
        int maximumBatchSize,
        int totalChunks,
        String manifestHash,
        boolean listingEvidenceComplete,
        boolean databaseWritesPerformed,
        List<Instrument> instruments,
        String detail
) {
    public ExpansionBatchPreview {
        instruments = List.copyOf(instruments);
    }

    public record Instrument(
            String symbol,
            String providerInstrumentKey,
            LocalDate listedOn,
            LocalDate nseReportedListedOn,
            String listingBoundaryStatus,
            LocalDate providerPrelistingCandleOn,
            LocalDate effectiveFrom,
            int totalChunks
    ) {
    }
}
