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
        List<String> normalizationDetails,
        String detail
) {
    public UpstoxImportResult {
        normalizedDuplicateDates = normalizedDuplicateDates == null
                ? List.of() : List.copyOf(normalizedDuplicateDates);
        normalizationDetails = normalizationDetails == null
                ? List.of() : List.copyOf(normalizationDetails);
    }

    public static UpstoxImportResult providerFailure(UpstoxFetchResult<?> result) {
        return new UpstoxImportResult(result.status(), 0, 0, 0, 0, List.of(), List.of(), result.detail());
    }
}
