package in.marketbrain.configuration;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.math.BigDecimal;

@Validated
@ConfigurationProperties(prefix = "marketbrain")
public record MarketBrainProperties(
        @NotBlank String executionMode,
        @Valid Paper paper,
        @Valid Ollama ollama,
        @Valid Signal signal,
        @Valid PaytmMoney paytmMoney,
        @Valid Upstox upstox,
        @Valid Telegram telegram
) {
    public record Paper(@DecimalMin("0.00") BigDecimal startingCash) {
    }

    public record Ollama(@NotBlank String baseUrl) {
    }

    public record Signal(
            @Min(1) int maximumDataAgeSeconds,
            @Min(1) int targetAlertSubmissionSeconds
    ) {
    }

    /**
     * The access token is intentionally optional.  A disabled or unconfigured
     * provider must never make an external request.
     */
    public record PaytmMoney(
            @NotBlank String baseUrl,
            boolean enabled,
            String accessToken
    ) {
        public boolean isConfigured() {
            return enabled && accessToken != null && !accessToken.isBlank();
        }
    }

    /**
     * Read-only Upstox Analytics Token configuration. The token is optional so
     * a fresh installation remains inert until explicitly enabled locally.
     */
    public record Upstox(
            @NotBlank String baseUrl,
            @NotBlank String nseInstrumentUrl,
            boolean enabled,
            String analyticsToken
    ) {
        public boolean isConfigured() {
            return enabled && analyticsToken != null && !analyticsToken.isBlank();
        }
    }

    /**
     * Telegram remains inert until explicitly enabled and supplied with local
     * secrets. Neither the bot token nor pairing code is exposed by an API.
     */
    public record Telegram(
            boolean enabled,
            String botToken,
            String pairingCode,
            @Min(1) int longPollTimeoutSeconds,
            @Min(100) int pollDelayMillis,
            boolean testAlertsEnabled
    ) {
        public boolean isConfigured() {
            return enabled
                    && botToken != null && !botToken.isBlank()
                    && pairingCode != null && pairingCode.length() >= 16;
        }
    }
}
