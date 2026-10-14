package in.marketbrain.paper;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import javax.sql.DataSource;
import java.nio.file.Path;
import java.time.*;
import java.util.Arrays;

/** Default off. Enabling requires separately reviewed credential, route and policy deployment.
 * No Tailscale, browser access or public webhook is required. No publisher or order executor is registered here.
 */
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(prefix = "marketbrain.paper.review", name = "enabled", havingValue = "true")
public class PaperTelegramReviewConfiguration {
    record Settings(PaperWriterConnector.Target target, Path credentialFile, PaperApprovalReview.PolicyVersion policy) {}

    @Bean Settings paperReviewSettings(Environment environment, MarketBrainProperties app) {
        try {
            if (!"PAPER".equals(app.executionMode()) || app.telegram() == null || !app.telegram().isConfigured()
                    || app.upstox() == null || !app.upstox().isConfigured()
                    || !"REVIEW_ONLY".equals(required(environment, "activation"))
                    || !"PRIVATE_SAME_MACHINE".equals(required(environment, "transport")))
                throw new IllegalArgumentException();
            var target = new PaperWriterConnector.Target(required(environment, "host"),
                    Integer.parseInt(required(environment, "port")), required(environment, "database"),
                    Long.parseLong(required(environment, "database-oid")), PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE, null);
            var path = Path.of(required(environment, "credential-file"));
            // Fail an explicit opt-in before polling if the mount is missing/malformed. No DB connection here.
            char[] credential = PaperReviewWiring.readCredential(path);
            Arrays.fill(credential, '\0');
            var limits = new PaperAccountEngineering.Policy(number(environment, "max-quote-age-millis"),
                    Math.toIntExact(number(environment, "max-slippage-bps")), number(environment, "max-quantity"),
                    number(environment, "max-order-notional-paise"), Math.toIntExact(number(environment, "max-approvals")),
                    Math.toIntExact(number(environment, "max-fills")));
            var policy = new PaperApprovalReview.PolicyVersion(required(environment, "policy-id"), "UPSTOX", limits,
                    Duration.ofSeconds(number(environment, "max-proposal-lifetime-seconds")));
            return new Settings(target, path, policy);
        } catch (Exception invalid) {
            throw new IllegalStateException("Paper Telegram review opt-in configuration is incomplete or invalid; no review activated");
        }
    }

    @Bean(destroyMethod = "close") PaperApprovalHttp.BoundedTransport paperReviewTransport(Settings settings) {
        return new PaperApprovalHttp.BoundedTransport();
    }

    @Bean PaperApprovalCallback paperApprovalCallback(Settings settings, PaperApprovalHttp.BoundedTransport transport,
            MarketBrainProperties app, DataSource applicationReadSource) {
        Clock clock = Clock.systemUTC();
        // General datasource is used ONLY for the existing read-only instrument-key lookup, never review writes.
        var quotes = PaperApprovalHttp.upstox(transport,
                PaperApprovalHttp.jdbcInstrumentKeys(applicationReadSource::getConnection),
                () -> app.upstox().analyticsToken(), clock);
        return PaperReviewWiring.callback(settings.target(), settings.credentialFile(), quotes, clock, settings.policy());
    }

    private static String required(Environment env, String name) {
        String value = env.getProperty("marketbrain.paper.review." + name);
        if (value == null || value.isBlank()) throw new IllegalArgumentException();
        return value;
    }
    private static long number(Environment env, String name) { return Long.parseLong(required(env, name)); }
}
