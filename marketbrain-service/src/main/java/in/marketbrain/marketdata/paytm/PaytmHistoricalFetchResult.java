package in.marketbrain.marketdata.paytm;

/**
 * Contains only provider status and response data. Provider timestamps and raw
 * payload persistence will be added by the collector, not by this feasibility client.
 */
public record PaytmHistoricalFetchResult(String status, int httpStatus, String responseBody, String detail) {

    public static PaytmHistoricalFetchResult notConfigured() {
        return new PaytmHistoricalFetchResult(
                "NOT_CONFIGURED", 0, null,
                "Paytm Money is disabled or has no local access token.");
    }
}
