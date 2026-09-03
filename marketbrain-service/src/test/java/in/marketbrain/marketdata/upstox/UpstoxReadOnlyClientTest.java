package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.time.LocalDate;
import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

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

    @Test
    void classifiesNetworkFailureAsSafelyRetryable() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = client(builder, true, "analytics-token-value");
        server.expect(once(), requestTo(
                        "https://api.upstox.com/v3/historical-candle/NSE_EQ%7CINE009A01021/days/1/2026-09-01/2026-08-25"))
                .andRespond(withException(new IOException("simulated offline connection")));

        var result = client.fetchHistoricalCandles(historicalRequest());

        assertThat(result.status()).isEqualTo("CONNECTION_FAILED");
        assertThat(result.detail()).doesNotContain("simulated offline connection");
        server.verify();
    }

    @Test
    void classifiesRateLimitAndProviderOutageAsTransient() {
        RestClient.Builder rateLimitedBuilder = RestClient.builder();
        MockRestServiceServer rateLimitedServer = MockRestServiceServer.bindTo(rateLimitedBuilder).build();
        var rateLimitedClient = client(rateLimitedBuilder, true, "analytics-token-value");
        rateLimitedServer.expect(once(), requestTo(
                        "https://api.upstox.com/v3/historical-candle/NSE_EQ%7CINE009A01021/days/1/2026-09-01/2026-08-25"))
                .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));

        assertThat(rateLimitedClient.fetchHistoricalCandles(historicalRequest()).status())
                .isEqualTo("RATE_LIMITED");
        rateLimitedServer.verify();

        RestClient.Builder unavailableBuilder = RestClient.builder();
        MockRestServiceServer unavailableServer = MockRestServiceServer.bindTo(unavailableBuilder).build();
        var unavailableClient = client(unavailableBuilder, true, "analytics-token-value");
        unavailableServer.expect(once(), requestTo(
                        "https://api.upstox.com/v3/historical-candle/NSE_EQ%7CINE009A01021/days/1/2026-09-01/2026-08-25"))
                .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        assertThat(unavailableClient.fetchHistoricalCandles(historicalRequest()).status())
                .isEqualTo("PROVIDER_UNAVAILABLE");
        unavailableServer.verify();
    }

    @Test
    void malformedProviderDataIsNotClassifiedAsConnectivityFailure() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = client(builder, true, "analytics-token-value");
        server.expect(once(), requestTo(
                        "https://api.upstox.com/v3/historical-candle/NSE_EQ%7CINE009A01021/days/1/2026-09-01/2026-08-25"))
                .andRespond(withSuccess("not-json", MediaType.APPLICATION_JSON));

        var result = client.fetchHistoricalCandles(historicalRequest());

        assertThat(result.status()).isEqualTo("INVALID_PROVIDER_RESPONSE");
        server.verify();
    }

    @Test
    void requestsCorporateActionsByIsinWithTheReadOnlyToken() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = client(builder, true, "analytics-token-value");
        server.expect(once(), requestTo(
                        "https://api.upstox.com/v2/fundamentals/INE914M01019/corporate-actions"))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer analytics-token-value"))
                .andRespond(withSuccess("{\"status\":\"success\",\"data\":[]}",
                        MediaType.APPLICATION_JSON));

        var result = client.fetchCorporateActions("INE914M01019");

        assertThat(result.status()).isEqualTo("SUCCESS");
        server.verify();
    }

    private UpstoxHistoricalRequest historicalRequest() {
        return new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "days", 1,
                LocalDate.of(2026, 8, 25), LocalDate.of(2026, 9, 1));
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
