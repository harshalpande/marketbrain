package in.marketbrain.marketdata.backfill;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

public record QualityResolutionRecord(
        UUID id,
        UUID jobId,
        String symbol,
        QualityFindingType findingType,
        LocalDate findingDate,
        LocalDate relatedDate,
        QualityResolutionType resolutionType,
        boolean allowsTraining,
        String evidenceSource,
        String evidenceUrl,
        String notes,
        String reviewedBy,
        LocalDate exclusionFrom,
        LocalDate exclusionTo,
        Instant createdAt
) {
}
