package in.marketbrain.marketdata.paytm;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Read-only, manually invoked client for Paytm Money historical candles.
 * No scheduler calls this client. It has no order-placement capability.
 */
@Component
public class PaytmMoneyHistoricalClient {

    private static final String HISTORICAL_PATH = "/data/v1/price-charts/sym";

    private final RestClient restClient;
    private final MarketBrainProperties.PaytmMoney paytmMoney;

    public PaytmMoneyHistoricalClient(RestClient.Builder restClientBuilder, MarketBrainProperties properties) {
        this.paytmMoney = properties.paytmMoney();
        this.restClient = restClientBuilder.baseUrl(paytmMoney.baseUrl()).build();
    }

    public PaytmHistoricalFetchResult fetchCandles(PaytmHistoricalCandleRequest request) {
        if (!paytmMoney.isConfigured()) {
            return PaytmHistoricalFetchResult.notConfigured();
        }

        try {
            var response = restClient.post()
                    .uri(HISTORICAL_PATH)
                    .contentType(MediaType.APPLICATION_JSON)
                    .header("x-jwt-token", paytmMoney.accessToken())
                    .body(request.asRequestBody())
                    .retrieve()
                    .toEntity(String.class);
            return new PaytmHistoricalFetchResult(
                    response.getStatusCode().is2xxSuccessful() ? "SUCCESS" : "PROVIDER_ERROR",
                    response.getStatusCode().value(),
                    response.getBody(),
                    "Historical response received; validate before ingestion.");
        } catch (RestClientException exception) {
            return new PaytmHistoricalFetchResult(
                    "CONNECTION_FAILED", 0, null,
                    "Paytm Money historical request could not be completed: " + exception.getClass().getSimpleName());
        }
    }
}
