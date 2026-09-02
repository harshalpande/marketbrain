package in.marketbrain.marketdata.upstox;

import java.math.BigDecimal;
import java.time.Instant;

public record UpstoxQuoteResult(
        String status,
        String instrumentKey,
        String tradingSymbol,
        BigDecimal lastPrice,
        Instant providerPublishedAt,
        Instant lastTradeAt,
        String qualityStatus,
        long ageSeconds,
        boolean actionable,
        boolean persisted,
        String detail
) {
    public static UpstoxQuoteResult providerFailure(String instrumentKey, UpstoxFetchResult<?> result) {
        return new UpstoxQuoteResult(result.status(), instrumentKey, null, null, null, null,
                "UNAVAILABLE", -1, false, false, result.detail());
    }
}
