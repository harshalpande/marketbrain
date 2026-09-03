package in.marketbrain.marketdata.backfill;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.util.UUID;

public record QualityResolutionRevocationRequest(
        @NotNull UUID jobId,
        @Size(max = 64) String symbol,
        @NotNull QualityFindingType findingType,
        @NotNull LocalDate findingDate,
        LocalDate relatedDate,
        @NotBlank @Size(max = 120) String evidenceSource,
        @NotBlank @Size(max = 500) @Pattern(regexp = "https://.+") String evidenceUrl,
        @NotBlank @Size(max = 1000) String notes,
        @NotBlank @Size(max = 120) String reviewedBy
) {
}
