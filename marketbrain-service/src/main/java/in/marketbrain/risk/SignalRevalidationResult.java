package in.marketbrain.risk;

import java.math.BigDecimal;

public record SignalRevalidationResult(
        Decision decision,
        BigDecimal revalidatedPrice,
        String reason
) {
    public enum Decision {
        APPROVED_FOR_PAPER_ORDER,
        LIVE_MODE_DISABLED,
        SIGNAL_EXPIRED,
        STALE_MARKET_DATA,
        BUY_PRICE_OUTSIDE_ZONE,
        SELL_PRICE_OUTSIDE_ZONE
    }
}
