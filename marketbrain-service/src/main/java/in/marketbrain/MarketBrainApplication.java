package in.marketbrain;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableConfigurationProperties(MarketBrainProperties.class)
@EnableScheduling
public class MarketBrainApplication {

    public static void main(String[] args) {
        SpringApplication.run(MarketBrainApplication.class, args);
    }
}
