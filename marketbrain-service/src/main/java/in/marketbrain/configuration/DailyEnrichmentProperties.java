package in.marketbrain.configuration;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.time.ZoneId;
import java.time.LocalTime;
import java.util.List;

@Validated
@ConfigurationProperties(prefix = "marketbrain.daily-enrichment")
public record DailyEnrichmentProperties(
        boolean schedulerEnabled,
        @NotBlank String cron,
        @NotBlank String finalAttemptCron,
        @NotBlank String zone,
        @Min(1) @Max(366) int maximumCatchupDays,
        @NotBlank String providerWindowStart,
        @NotBlank String providerWindowCutoff,
        @Size(min = 1, max = 10) List<String> readinessSymbols,
        @Min(10_000) long completionMonitorDelayMillis
) {
    public DailyEnrichmentProperties {
        ZoneId.of(zone);
        LocalTime start = LocalTime.parse(providerWindowStart);
        LocalTime cutoff = LocalTime.parse(providerWindowCutoff);
        if (!start.isBefore(cutoff)) {
            throw new IllegalArgumentException("Provider window start must be before its cutoff");
        }
        readinessSymbols = List.copyOf(readinessSymbols);
    }
}
