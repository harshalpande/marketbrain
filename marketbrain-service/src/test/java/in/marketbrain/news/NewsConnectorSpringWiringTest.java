package in.marketbrain.news;

import com.fasterxml.jackson.databind.ObjectMapper;
import in.marketbrain.configuration.NewsProperties;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;

class NewsConnectorSpringWiringTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(NewsProperties.class, NewsConnectorSpringWiringTest::properties)
            .withBean(RestClient.Builder.class, RestClient::builder)
            .withBean(ObjectMapper.class, ObjectMapper::new)
            .withBean(MarketauxNewsResponseParser.class)
            .withBean(RssNewsFeedParser.class)
            .withBean(MarketauxNewsConnector.class)
            .withBean(RssNewsConnector.class);

    @Test
    void springSelectsProductionConstructorsForNewsConnectors() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(MarketauxNewsConnector.class);
            assertThat(context).hasSingleBean(RssNewsConnector.class);
        });
    }

    private static NewsProperties properties() {
        return new NewsProperties(false, false, 100, 20,
                new NewsProperties.Marketaux("https://api.marketaux.com/v1/news/all", ""));
    }
}
