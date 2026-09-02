package in.marketbrain.marketdata;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Safe provider inventory. It reports configuration only; it never performs a
 * credentialed call and never exposes a token.
 */
@RestController
@RequestMapping("/api/v1/data-sources")
public class MarketDataSourceController {

    private final ProviderCatalog providerCatalog;
    private final MarketBrainProperties properties;

    public MarketDataSourceController(ProviderCatalog providerCatalog, MarketBrainProperties properties) {
        this.providerCatalog = providerCatalog;
        this.properties = properties;
    }

    @GetMapping
    public List<ProviderStatus> providers() {
        return providerCatalog.plannedProviders().stream()
                .map(provider -> new ProviderStatus(
                        provider.code(),
                        provider.displayName(),
                        provider.capabilities(),
                        statusFor(provider.code()),
                        provider.implementationNote()))
                .toList();
    }

    private String statusFor(String code) {
        return switch (code) {
            case "PAYTM_MONEY" -> properties.paytmMoney().isConfigured()
                    ? "CONFIGURED_NOT_TESTED" : "DISABLED";
            case "UPSTOX" -> properties.upstox().isConfigured()
                    ? "CONFIGURED_READ_ONLY" : "DISABLED";
            default -> "PLANNED";
        };
    }

    public record ProviderStatus(
            String code,
            String displayName,
            java.util.Set<MarketDataCapability> capabilities,
            String status,
            String note
    ) {
    }
}
