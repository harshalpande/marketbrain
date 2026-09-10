package in.marketbrain.news;

import in.marketbrain.configuration.NewsProperties;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

@Component
public class MarketauxNewsConnector implements NewsConnector {

    private final RestClient restClient;
    private final NewsProperties properties;
    private final MarketauxNewsResponseParser parser;

    public MarketauxNewsConnector(
            RestClient.Builder builder,
            NewsProperties properties,
            MarketauxNewsResponseParser parser
    ) {
        this.restClient = builder.build();
        this.properties = properties;
        this.parser = parser;
    }

    @Override
    public NewsSourceIntegrationType integrationType() {
        return NewsSourceIntegrationType.MARKETAUX_API;
    }

    @Override
    public NewsFetchResult fetch(NewsFetchRequest request) {
        if (!properties.marketaux().isConfigured()) {
            return NewsFetchResult.skipped(request.source().sourceKey(), "Marketaux API token is not configured.");
        }
        String uri = UriComponentsBuilder.fromUriString(properties.marketaux().baseUrl())
                .queryParam("countries", "in")
                .queryParam("language", "en")
                .queryParam("filter_entities", "true")
                .queryParam("limit", request.limit())
                .queryParam("api_token", properties.marketaux().apiToken())
                .build(true)
                .toUriString();
        String payload = restClient.get()
                .uri(uri)
                .retrieve()
                .body(String.class);
        return new NewsFetchResult(
                request.source().sourceKey(),
                "FETCHED",
                1,
                parser.parse(request.source().sourceKey(), payload == null ? "" : payload),
                "Marketaux response parsed into permission-scoped article candidates.");
    }
}
