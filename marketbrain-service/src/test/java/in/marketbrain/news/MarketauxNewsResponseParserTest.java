package in.marketbrain.news;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class MarketauxNewsResponseParserTest {

    private final MarketauxNewsResponseParser parser = new MarketauxNewsResponseParser(new ObjectMapper());

    @Test
    void mapsMarketauxPayloadToArticleCandidates() {
        String payload = """
                {
                  "data": [
                    {
                      "uuid": "article-1",
                      "title": "Reliance announces new investment plan",
                      "description": "The company announced a new investment plan.",
                      "url": "https://example.test/reliance-investment",
                      "published_at": "2026-09-10T05:30:00Z",
                      "entities": [
                        {
                          "symbol": "RELIANCE",
                          "name": "Reliance Industries Ltd",
                          "exchange": "XNSE",
                          "country": "in",
                          "sentiment_score": 0.42,
                          "match_score": 76.5
                        }
                      ]
                    }
                  ]
                }
                """;

        var articles = parser.parse("MARKETAUX_API", payload);

        assertThat(articles).hasSize(1);
        NewsArticleCandidate article = articles.getFirst();
        assertThat(article.sourceKey()).isEqualTo("MARKETAUX_API");
        assertThat(article.providerItemId()).isEqualTo("article-1");
        assertThat(article.sourceDomain()).isEqualTo("example.test");
        assertThat(article.title()).contains("Reliance");
        assertThat(article.providerPublishedAt()).isNotNull();
        assertThat(article.entities()).hasSize(1);
        assertThat(article.entities().getFirst().symbol()).isEqualTo("RELIANCE");
    }
}
