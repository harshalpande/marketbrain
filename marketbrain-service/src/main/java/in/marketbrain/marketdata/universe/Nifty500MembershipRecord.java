package in.marketbrain.marketdata.universe;

import java.time.LocalDate;
import java.util.Objects;

/**
 * A membership period, rather than a permanent list membership. This prevents
 * future index constituents leaking into historical strategy and backtest data.
 */
public record Nifty500MembershipRecord(
        String symbol,
        String isin,
        String companyName,
        LocalDate effectiveFrom,
        LocalDate effectiveTo
) {
    public Nifty500MembershipRecord {
        requireText(symbol, "symbol");
        requireText(isin, "isin");
        requireText(companyName, "companyName");
        Objects.requireNonNull(effectiveFrom, "effectiveFrom is required");
        if (effectiveTo != null && effectiveTo.isBefore(effectiveFrom)) {
            throw new IllegalArgumentException("effectiveTo must be on or after effectiveFrom");
        }
    }

    private static void requireText(String value, String fieldName) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(fieldName + " is required");
        }
    }
}
