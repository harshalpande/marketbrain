package in.marketbrain.marketdata;

import java.time.Instant;
import java.util.Set;

/**
 * Contract only. Implementations must use documented, licensed provider APIs and
 * preserve provider timestamps and provenance for every received market value.
 */
public interface MarketDataProvider {

    String code();

    Set<MarketDataCapability> capabilities();

    ProviderHealth health();

    record ProviderHealth(String status, Instant checkedAt, String detail) {
    }
}
