package in.marketbrain;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.configuration.DailyFeatureSnapshotProperties;
import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.configuration.HistoricalBackfillProperties;
import in.marketbrain.configuration.NewsProperties;
import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableConfigurationProperties({
        MarketBrainProperties.class,
        HistoricalBackfillProperties.class,
        DailyEnrichmentProperties.class,
        DailyFeatureSnapshotProperties.class,
        NewsProperties.class,
        WhatsAppProperties.class
})
@EnableScheduling
public class MarketBrainApplication {

    public static void main(String[] args) {
        SpringApplication.run(MarketBrainApplication.class, args);
    }
}
