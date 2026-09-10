package in.marketbrain.configuration;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "marketbrain.news")
public record NewsProperties(
        boolean enabled,
        boolean liveFetchEnabled,
        @Min(1) int maximumArticlesPerDay,
        @Min(1) int requestTimeoutSeconds,
        Marketaux marketaux
) {
    public NewsProperties {
        if (marketaux == null) {
            marketaux = new Marketaux("https://api.marketaux.com/v1/news/all", "");
        }
    }

    public boolean canMakeProviderRequests() {
        return enabled && liveFetchEnabled;
    }

    public record Marketaux(
            @NotBlank String baseUrl,
            String apiToken
    ) {
        public boolean isConfigured() {
            return apiToken != null && !apiToken.isBlank();
        }
    }
}
