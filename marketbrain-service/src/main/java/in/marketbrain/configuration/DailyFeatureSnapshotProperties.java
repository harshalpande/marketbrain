package in.marketbrain.configuration;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.time.LocalDate;

@Validated
@ConfigurationProperties(prefix = "marketbrain.daily-feature-snapshot")
public record DailyFeatureSnapshotProperties(
        boolean enabled,
        @NotNull LocalDate activationDate,
        @Min(10_000) long monitorDelayMillis,
        @Min(1) @Max(10) int maximumAttempts
) {
}
