package in.marketbrain.marketdata.universe;

public record Nifty500SourceResult(String status, byte[] payload, String sha256, String detail) {
    public boolean succeeded() {
        return "SUCCESS".equals(status);
    }
}
