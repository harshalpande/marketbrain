package in.marketbrain.marketdata.universe;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record Nifty500SnapshotImportResult(
        String status,
        UUID snapshotId,
        LocalDate observedOn,
        int sourceMembers,
        int matchedMembers,
        int unmatchedMembers,
        List<String> unmatchedSymbols,
        String detail
) {
}
