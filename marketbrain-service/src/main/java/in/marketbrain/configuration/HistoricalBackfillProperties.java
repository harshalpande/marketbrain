package in.marketbrain.configuration;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.util.List;

@Validated
@ConfigurationProperties(prefix = "marketbrain.backfill")
public record HistoricalBackfillProperties(
        boolean workerEnabled,
        @NotBlank String currentNifty500Url,
        @NotBlank String nseEquitySecurityUrl,
        @Min(500) long workerDelayMillis,
        @Min(1) @Max(3) int maximumAttempts,
        @Min(1) @Max(50) int maximumExpansionBatchSize,
        @Size(min = 1, max = 10) List<String> pilotSymbols
) {
}
