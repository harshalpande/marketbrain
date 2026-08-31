package in.marketbrain.marketdata.paytm;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/**
 * Request shape for Paytm Money's documented historical-data beta endpoint.
 * This is limited to read-only candle retrieval; it contains no order fields.
 */
public record PaytmHistoricalCandleRequest(
        String exchange,
        String symbol,
        String instrumentType,
        String interval,
        LocalDate fromDate,
        LocalDate toDate
) {
    public PaytmHistoricalCandleRequest {
        requireText(exchange, "exchange");
        requireText(symbol, "symbol");
        requireText(instrumentType, "instrumentType");
        requireText(interval, "interval");
        Objects.requireNonNull(fromDate, "fromDate is required");
        Objects.requireNonNull(toDate, "toDate is required");
        if (toDate.isBefore(fromDate)) {
            throw new IllegalArgumentException("toDate must be on or after fromDate");
        }
    }

    public Map<String, String> asRequestBody() {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("exchange", exchange);
        body.put("symbol", symbol);
        body.put("instType", instrumentType);
        body.put("interval", interval);
        body.put("fromDate", fromDate.toString());
        body.put("toDate", toDate.toString());
        return body;
    }

    private static void requireText(String value, String fieldName) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(fieldName + " is required");
        }
    }
}
