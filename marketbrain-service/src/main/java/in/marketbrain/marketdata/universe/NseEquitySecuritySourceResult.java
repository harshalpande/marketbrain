package in.marketbrain.marketdata.universe;

public record NseEquitySecuritySourceResult(
        String status,
        byte[] payload,
        String sha256,
        String detail
) {
    public boolean succeeded() {
        return "SUCCESS".equals(status);
    }
}
