package in.marketbrain.marketdata;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Set;

/**
 * Declares intended data-provider roles before any credentialed connection is enabled.
 */
@Component
public class ProviderCatalog {

    public List<ProviderDefinition> plannedProviders() {
        return List.of(
                new ProviderDefinition(
                        "PAYTM_MONEY",
                        "Paytm Money Open API",
                        Set.of(MarketDataCapability.INTRADAY_QUOTES, MarketDataCapability.HISTORICAL_CANDLES,
                                MarketDataCapability.POSITIONS, MarketDataCapability.ORDERS, MarketDataCapability.TRADES),
                        "Deferred broker candidate. Historical API is documented as beta; disabled until a local "
                                + "read-only feasibility check succeeds."
                ),
                new ProviderDefinition(
                        "UPSTOX",
                        "Upstox Developer API",
                        Set.of(MarketDataCapability.INTRADAY_QUOTES, MarketDataCapability.HISTORICAL_CANDLES,
                                MarketDataCapability.CORPORATE_ACTIONS, MarketDataCapability.NEWS_EVENTS),
                        "Primary read-only provider. Manual REST ingestion and corporate-action evidence are "
                                + "implemented; automated collection remains separately controlled."
                ),
                new ProviderDefinition(
                        "NSE_DATA",
                        "NSE Data and Analytics",
                        Set.of(MarketDataCapability.HISTORICAL_CANDLES, MarketDataCapability.CORPORATE_ACTIONS,
                                MarketDataCapability.COMPANY_FILINGS),
                        "Licensed fallback subject to provider agreement and pricing."
                )
        );
    }

    public record ProviderDefinition(String code, String displayName, Set<MarketDataCapability> capabilities,
                                     String implementationNote) {
    }
}
