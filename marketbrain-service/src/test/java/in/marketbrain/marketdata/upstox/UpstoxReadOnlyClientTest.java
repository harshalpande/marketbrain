package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class UpstoxReadOnlyClientTest {

    @Test
    void sendsBearerTokenAndCorrectHistoricalPathOrder() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = client(builder, true, "analytics-token-value");
        server.expect(once(), requestTo(
                        "https://api.upstox.com/v3/historical-candle/NSE_EQ%7CINE009A01021/days/1/2026-09-01/2026-08-25"))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer analytics-token-value"))
                .andRespond(withSuccess("{\"status\":\"success\",\"data\":{\"candles\":[]}}",
                        MediaType.APPLICATION_JSON));

        var result = client.fetchHistoricalCandles(new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "days", 1,
                LocalDate.of(2026, 8, 25), LocalDate.of(2026, 9, 1)));

        assertThat(result.status()).isEqualTo("SUCCESS");
        server.verify();
    }

    @Test
    void disabledConfigurationPerformsNoRequest() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = client(builder, false, "analytics-token-value");

        var result = client.fetchFullQuote("NSE_EQ|INE009A01021");

        assertThat(result.status()).isEqualTo("NOT_CONFIGURED");
        server.verify();
    }

    private UpstoxReadOnlyClient client(RestClient.Builder builder, boolean enabled, String token) {
        var upstox = new MarketBrainProperties.Upstox(
                "https://api.upstox.com",
                "https://assets.upstox.com/market-quote/instruments/exchange/NSE.json.gz",
                enabled,
                token);
        return new UpstoxReadOnlyClient(
                builder.baseUrl(upstox.baseUrl()).build(),
                upstox,
                new UpstoxResponseParser(new ObjectMapper()));
    }
}
