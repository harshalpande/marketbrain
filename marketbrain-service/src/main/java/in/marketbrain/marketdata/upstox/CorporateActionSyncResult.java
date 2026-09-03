package in.marketbrain.marketdata.upstox;

import java.util.List;

public record CorporateActionSyncResult(
        String status,
        String symbol,
        String isin,
        int received,
        int accepted,
        int rejected,
        List<CorporateActionEvidence> events,
        String detail
) {
    static CorporateActionSyncResult providerFailure(String symbol, String isin, UpstoxFetchResult<?> fetch) {
        return new CorporateActionSyncResult(
                fetch.status(), symbol, isin, 0, 0, 0, List.of(), fetch.detail());
    }
}
