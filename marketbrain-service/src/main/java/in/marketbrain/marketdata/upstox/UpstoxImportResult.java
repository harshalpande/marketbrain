package in.marketbrain.marketdata.upstox;

import java.time.LocalDate;
import java.util.List;

public record UpstoxImportResult(
        String status,
        int received,
        int accepted,
        int rejected,
        int normalizedDuplicates,
        List<LocalDate> normalizedDuplicateDates,
        String detail
) {
    public UpstoxImportResult {
        normalizedDuplicateDates = normalizedDuplicateDates == null
                ? List.of() : List.copyOf(normalizedDuplicateDates);
    }

    public static UpstoxImportResult providerFailure(UpstoxFetchResult<?> result) {
        return new UpstoxImportResult(result.status(), 0, 0, 0, 0, List.of(), result.detail());
    }
}
