package in.marketbrain.marketdata.upstox;

import java.math.BigDecimal;
import java.time.Instant;

public record UpstoxQuote(
        String instrumentKey,
        String tradingSymbol,
        BigDecimal lastPrice,
        BigDecimal previousClose,
        BigDecimal volume,
        Instant providerPublishedAt,
        Instant lastTradeAt
) {
}
