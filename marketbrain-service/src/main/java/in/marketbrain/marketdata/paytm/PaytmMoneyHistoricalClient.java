package in.marketbrain.marketdata.paytm;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.stereotype.Component;

/**
 * Read-only, manually invoked client for Paytm Money historical candles.
 * No scheduler calls this client. It has no order-placement capability.
 */
@Component
public class PaytmMoneyHistoricalClient {

    private final MarketBrainProperties.PaytmMoney paytmMoney;

    public PaytmMoneyHistoricalClient(MarketBrainProperties properties) {
        this.paytmMoney = properties.paytmMoney();
    }

    public PaytmHistoricalFetchResult fetchCandles(PaytmHistoricalCandleRequest request) {
        if (!paytmMoney.isConfigured()) {
            return PaytmHistoricalFetchResult.notConfigured();
        }

        // The old direct RestClient path is deliberately retired. The diagnostic lease
        // never authorizes credentials or POST requests. Restore data access only after
        // a separately verified gateway-backed authentication/data client is implemented.
        return new PaytmHistoricalFetchResult("AUTHENTICATION_AND_DATA_INTEGRATION_PENDING", 0, null,
                "Historical access is locked pending reviewed gateway-backed authentication and data integration.");
    }
}
