package in.marketbrain.risk;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * The immutable information required to decide whether an alert approval can
 * create a PAPER order. Prices are BigDecimal to avoid floating point errors.
 */
public record SignalRevalidationRequest(
        String executionMode,
        SignalAction action,
        boolean protectiveExit,
        Instant validUntil,
        BigDecimal acceptablePriceMin,
        BigDecimal acceptablePriceMax,
        BigDecimal referencePrice,
        BigDecimal latestPrice,
        Instant latestPriceAt,
        Instant assessedAt
) {
}
