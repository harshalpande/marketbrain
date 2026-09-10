package in.marketbrain.news;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class RssNewsFeedParserTest {

    private final RssNewsFeedParser parser = new RssNewsFeedParser();

    @Test
    void mapsRssItemsToArticleCandidates() {
        String payload = """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Market news</title>
                    <item>
                      <guid>item-1</guid>
                      <title>HDFC Bank board approves capital raise</title>
                      <link>https://example.test/hdfc-bank-capital</link>
                      <description>Board approval has been reported.</description>
                      <pubDate>Thu, 10 Sep 2026 08:00:00 GMT</pubDate>
                    </item>
                  </channel>
                </rss>
                """;

        var articles = parser.parse("BUSINESS_STANDARD_RSS", payload);

        assertThat(articles).hasSize(1);
        NewsArticleCandidate article = articles.getFirst();
        assertThat(article.sourceKey()).isEqualTo("BUSINESS_STANDARD_RSS");
        assertThat(article.providerItemId()).isEqualTo("item-1");
        assertThat(article.sourceDomain()).isEqualTo("example.test");
        assertThat(article.title()).contains("HDFC Bank");
        assertThat(article.providerPublishedAt()).isNotNull();
        assertThat(article.entities()).isEmpty();
    }
}
