package in.marketbrain.marketdata.upstox;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import org.springframework.http.client.SimpleClientHttpRequestFactory;
import java.time.Duration;
import java.util.List;

/**
 * Upstox market-data client. It intentionally exposes no order, position, funds,
 * or portfolio endpoint and never sends a request while configuration is off.
 */
@Component
public class UpstoxReadOnlyClient {

    private final RestClient restClient;
    private final MarketBrainProperties.Upstox upstox;
    private final UpstoxResponseParser parser;

    @Autowired
    public UpstoxReadOnlyClient(
            RestClient.Builder restClientBuilder,
            MarketBrainProperties properties,
            UpstoxResponseParser parser
    ) {
        this(configuredClient(restClientBuilder, properties.upstox()), properties.upstox(), parser);
    }

    UpstoxReadOnlyClient(
            RestClient restClient,
            MarketBrainProperties.Upstox upstox,
            UpstoxResponseParser parser
    ) {
        this.restClient = restClient;
        this.upstox = upstox;
        this.parser = parser;
    }

    public UpstoxFetchResult<List<UpstoxInstrument>> fetchNseInstruments() {
        if (!upstox.isConfigured()) {
            return UpstoxFetchResult.notConfigured();
        }
        try {
            byte[] body = restClient.get()
                    .uri(upstox.nseInstrumentUrl())
                    .accept(MediaType.APPLICATION_OCTET_STREAM, MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(byte[].class);
            return UpstoxFetchResult.success(parser.parseInstruments(body));
        } catch (RestClientResponseException exception) {
            return providerFailure(exception);
        } catch (RestClientException | java.io.IOException exception) {
            return connectionFailure(exception);
        }
    }

    public UpstoxFetchResult<UpstoxQuote> fetchFullQuote(String instrumentKey) {
        if (!upstox.isConfigured()) {
            return UpstoxFetchResult.notConfigured();
        }
        try {
            String body = restClient.get()
                    .uri(builder -> builder.path("/v2/market-quote/quotes")
                            .queryParam("instrument_key", instrumentKey)
                            .build())
                    .header(HttpHeaders.AUTHORIZATION, bearerToken())
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(String.class);
            return UpstoxFetchResult.success(parser.parseQuote(body, instrumentKey));
        } catch (RestClientResponseException exception) {
            return providerFailure(exception);
        } catch (RestClientException | java.io.IOException exception) {
            return connectionFailure(exception);
        }
    }

    public UpstoxFetchResult<List<UpstoxCandle>> fetchHistoricalCandles(UpstoxHistoricalRequest request) {
        if (!upstox.isConfigured()) {
            return UpstoxFetchResult.notConfigured();
        }
        try {
            String body = restClient.get()
                    .uri(builder -> builder.pathSegment(
                                    "v3", "historical-candle", request.instrumentKey(), request.unit(),
                                    Integer.toString(request.interval()), request.toDate().toString(),
                                    request.fromDate().toString())
                            .build())
                    .header(HttpHeaders.AUTHORIZATION, bearerToken())
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(String.class);
            return UpstoxFetchResult.success(parser.parseCandles(body));
        } catch (RestClientResponseException exception) {
            return providerFailure(exception);
        } catch (RestClientException | java.io.IOException exception) {
            return connectionFailure(exception);
        }
    }

    private String bearerToken() {
        return "Bearer " + upstox.analyticsToken();
    }

    private static RestClient configuredClient(
            RestClient.Builder builder,
            MarketBrainProperties.Upstox properties
    ) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(45));
        return builder.requestFactory(requestFactory).baseUrl(properties.baseUrl()).build();
    }

    private <T> UpstoxFetchResult<T> providerFailure(RestClientResponseException exception) {
        return UpstoxFetchResult.failure(
                "PROVIDER_ERROR",
                exception.getStatusCode().value(),
                "Upstox rejected the read-only request. Check token validity, request values, and provider limits."
        );
    }

    private <T> UpstoxFetchResult<T> connectionFailure(Exception exception) {
        return UpstoxFetchResult.failure(
                "CONNECTION_OR_FORMAT_FAILED",
                0,
                "Upstox response could not be safely consumed: " + exception.getClass().getSimpleName()
        );
    }
}
