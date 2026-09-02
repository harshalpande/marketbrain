package in.marketbrain.marketdata.upstox;

public record UpstoxImportResult(
        String status,
        int received,
        int accepted,
        int rejected,
        String detail
) {
    public static UpstoxImportResult providerFailure(UpstoxFetchResult<?> result) {
        return new UpstoxImportResult(result.status(), 0, 0, 0, result.detail());
    }
}
