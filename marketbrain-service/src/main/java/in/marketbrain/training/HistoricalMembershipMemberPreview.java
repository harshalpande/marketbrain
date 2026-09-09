package in.marketbrain.training;

import java.time.LocalDate;

public record HistoricalMembershipMemberPreview(
        String sourceSymbol,
        String sourceIsin,
        String companyName,
        LocalDate effectiveFrom,
        LocalDate effectiveTo,
        String matchStatus,
        Long instrumentId,
        String currentSymbol,
        String matchBasis
) {
}
