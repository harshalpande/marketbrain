package in.marketbrain.marketdata.upstox;

public record MarketDataQuality(String status, long ageSeconds, String detail) {
    public boolean isUsableForAction() {
        return "FRESH".equals(status);
    }
}
