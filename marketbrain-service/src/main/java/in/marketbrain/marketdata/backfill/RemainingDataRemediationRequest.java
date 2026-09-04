package in.marketbrain.marketdata.backfill;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.UUID;

public record RemainingDataRemediationRequest(
        @NotNull UUID jobId,
        @NotBlank @Pattern(regexp = "[0-9a-f]{64}") String expectedPlanHash,
        @NotBlank @Size(max = 120) String reviewedBy
) {
}

