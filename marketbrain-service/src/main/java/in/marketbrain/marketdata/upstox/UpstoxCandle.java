package in.marketbrain.marketdata.upstox;

import java.math.BigDecimal;
import java.time.Instant;

public record UpstoxCandle(
        Instant openedAt,
        BigDecimal open,
        BigDecimal high,
        BigDecimal low,
        BigDecimal close,
        BigDecimal volume
) {
}
