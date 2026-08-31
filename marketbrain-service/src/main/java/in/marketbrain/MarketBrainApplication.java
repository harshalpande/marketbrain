package in.marketbrain;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(MarketBrainProperties.class)
public class MarketBrainApplication {

    public static void main(String[] args) {
        SpringApplication.run(MarketBrainApplication.class, args);
    }
}
