package in.marketbrain.configuration;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.time.ZoneId;

@Validated
@ConfigurationProperties(prefix = "marketbrain.daily-enrichment")
public record DailyEnrichmentProperties(
        boolean schedulerEnabled,
        @NotBlank String cron,
        @NotBlank String zone,
        @Min(1) @Max(366) int maximumCatchupDays
) {
    public DailyEnrichmentProperties {
        ZoneId.of(zone);
    }
}
