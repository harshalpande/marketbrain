package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record UpstoxInstrument(
        String segment,
        String name,
        String isin,
        @JsonProperty("instrument_type") String instrumentType,
        @JsonProperty("instrument_key") String instrumentKey,
        @JsonProperty("trading_symbol") String tradingSymbol,
        @JsonProperty("short_name") String shortName
) {
    public boolean isNseEquity() {
        return "NSE_EQ".equals(segment)
                && "EQ".equals(instrumentType)
                && hasText(instrumentKey)
                && hasText(tradingSymbol)
                && hasText(name);
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
