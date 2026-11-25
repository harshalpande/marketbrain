package in.marketbrain.paper;

import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import java.nio.file.Path;

/** Default-off, review-only publisher wiring. No HTTP endpoint, scheduler or order executor. */
@Configuration(proxyBeanMethods=false)
@ConditionalOnProperty(prefix="marketbrain.paper.publisher",name="enabled",havingValue="true")
public class PaperPublisherConfiguration {
    static final Path CONTROL=Path.of("/run/marketbrain-publisher");
    @Bean(destroyMethod="close") PaperPublisherRuntime paperPublisherRuntime(Environment env,
            MarketBrainProperties app, PaperTelegramReviewConfiguration.Settings settings,
            PaperApprovalCallback callback, PaytmPaperReviewAdapter quotes, PaperApprovalHttp.BoundedTransport transport) {
        if(!"PAPER".equals(app.executionMode()) || !settings.processMemory()
                || !PaperReviewTestPolicy.paytmPolicy().equals(settings.policy())
                || !"REVIEW_ONLY".equals(env.getProperty("marketbrain.paper.publisher.activation"))
                || !"PROCESS_MEMORY".equals(env.getProperty("marketbrain.paper.publisher.credential-mode"))
                || env.containsProperty("marketbrain.paper.publisher.credential-file")
                || app.telegram()==null || !app.telegram().isConfigured())
            throw new IllegalStateException("Publisher opt-in configuration invalid");
        String key=env.getProperty("marketbrain.paper.approval-key-file","");
        if(key.isBlank() || !Path.of(key).isAbsolute())throw new IllegalStateException("Existing approval key path required");
        return new PaperPublisherRuntime(settings.target(),quotes,
                PaperApprovalHttp.telegram(transport,()->app.telegram().botToken(),quotes.clock()),key);
    }
    @Bean(destroyMethod="close") PaperRuntimeControlServer paperPublisherControlServer(PaperPublisherRuntime runtime) throws java.io.IOException {
        return new PaperRuntimeControlServer(runtime.credential(),CONTROL);
    }
}
