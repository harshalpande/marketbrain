package in.marketbrain.marketdata.universe;

public record CurrentNifty500Constituent(
        String companyName,
        String industry,
        String symbol,
        String series,
        String isin
) {
    public boolean isCashEquity() {
        return "EQ".equalsIgnoreCase(series)
                && symbol != null && !symbol.isBlank()
                && isin != null && !isin.isBlank();
    }
}
