package in.marketbrain.marketdata.upstox;

public record UpstoxFetchResult<T>(
        String status,
        int providerStatusCode,
        T data,
        String detail
) {
    public static <T> UpstoxFetchResult<T> notConfigured() {
        return new UpstoxFetchResult<>("NOT_CONFIGURED", 0, null,
                "Upstox is disabled or its Analytics Token is absent.");
    }

    public static <T> UpstoxFetchResult<T> success(T data) {
        return new UpstoxFetchResult<>("SUCCESS", 200, data, "Read-only provider response validated.");
    }

    public static <T> UpstoxFetchResult<T> failure(String status, int providerStatusCode, String detail) {
        return new UpstoxFetchResult<>(status, providerStatusCode, null, detail);
    }

    public boolean succeeded() {
        return "SUCCESS".equals(status);
    }
}
