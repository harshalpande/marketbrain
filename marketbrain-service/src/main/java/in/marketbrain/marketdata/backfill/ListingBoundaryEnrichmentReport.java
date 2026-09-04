package in.marketbrain.marketdata.backfill;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record ListingBoundaryEnrichmentReport(
        String status,
        UUID snapshotId,
        int batchNumber,
        String inputManifestHash,
        String outputManifestHash,
        String sourceUrl,
        String sourceSha256,
        int sourceRecordCount,
        int candidateCount,
        int matchedEvidenceCount,
        int beforeRequestWindowCount,
        int existingBoundaryCount,
        int verifiedBoundaryCount,
        int earlierProviderHistoryCount,
        int providerRequestCount,
        int providerCheckFailureCount,
        int evidenceRowsWritten,
        int boundariesApplied,
        boolean listingEvidenceComplete,
        boolean databaseWritesPerformed,
        List<Item> items,
        String detail
) {
    public ListingBoundaryEnrichmentReport {
        items = List.copyOf(items);
    }

    public record Item(
            String symbol,
            String isin,
            String providerInstrumentKey,
            LocalDate nseReportedListedOn,
            LocalDate existingListedOn,
            LocalDate providerPrelistingCandleOn,
            String reconciliationStatus,
            int providerRequestCount,
            boolean boundaryApplied,
            String detail
    ) {
    }
}
