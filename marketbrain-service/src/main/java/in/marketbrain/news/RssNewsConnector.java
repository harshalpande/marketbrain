package in.marketbrain.news;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
class RssNewsConnector implements NewsConnector {

    private final RestClient restClient;
    private final RssNewsFeedParser parser;

    @Autowired
    RssNewsConnector(RestClient.Builder builder, RssNewsFeedParser parser) {
        this(builder.build(), parser);
    }

    RssNewsConnector(RestClient restClient, RssNewsFeedParser parser) {
        this.restClient = restClient;
        this.parser = parser;
    }

    @Override
    public NewsSourceIntegrationType integrationType() {
        return NewsSourceIntegrationType.RSS_FEED;
    }

    @Override
    public NewsFetchResult fetch(NewsFetchRequest request) {
        String payload = restClient.get()
                .uri(request.source().sourceUrl())
                .header(HttpHeaders.USER_AGENT, "MarketBrain personal research news monitor")
                .retrieve()
                .body(String.class);
        return new NewsFetchResult(
                request.source().sourceKey(),
                "FETCHED",
                1,
                parser.parse(request.source().sourceKey(), payload == null ? "" : payload),
                "RSS response parsed into permission-scoped article candidates.");
    }
}
