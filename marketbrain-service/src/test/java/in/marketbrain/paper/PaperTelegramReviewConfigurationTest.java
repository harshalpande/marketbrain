package in.marketbrain.paper;

import in.marketbrain.configuration.MarketBrainProperties;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import javax.sql.DataSource;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperTelegramReviewConfigurationTest {
    @TempDir Path directory;
    final DataSource source = mock(DataSource.class);
    MarketBrainProperties app(String mode, boolean telegram, boolean upstox) {
        return new MarketBrainProperties(mode, null, null, null, null,
                new MarketBrainProperties.Upstox("https://api.upstox.com", "unused", upstox, "synthetic-token"),
                new MarketBrainProperties.Telegram(telegram, "synthetic-token", "SYNTHETIC_PAIR_CODE", 20, 1000, false));
    }
    ApplicationContextRunner context(MarketBrainProperties app) {
        return new ApplicationContextRunner().withUserConfiguration(PaperTelegramReviewConfiguration.class)
                .withBean(DataSource.class, () -> source).withBean(MarketBrainProperties.class, () -> app);
    }
    String[] settings() throws Exception {
        Path file = directory.resolve("synthetic-writer-secret"); Files.writeString(file, "ab".repeat(32));
        return new String[]{"marketbrain.paper.review.enabled=true", "marketbrain.paper.review.activation=REVIEW_ONLY",
                "marketbrain.paper.review.transport=PRIVATE_SAME_MACHINE", "marketbrain.paper.review.host=127.0.0.1",
                "marketbrain.paper.review.port=5432", "marketbrain.paper.review.database=marketbrain",
                "marketbrain.paper.review.database-oid=16389", "marketbrain.paper.review.credential-file=" + file,
                "marketbrain.paper.review.policy-id=OFFLINE_ONLY", "marketbrain.paper.review.max-quote-age-millis=5000",
                "marketbrain.paper.review.max-slippage-bps=100", "marketbrain.paper.review.max-quantity=1",
                "marketbrain.paper.review.max-order-notional-paise=100000", "marketbrain.paper.review.max-approvals=1",
                "marketbrain.paper.review.max-fills=1", "marketbrain.paper.review.max-proposal-lifetime-seconds=120"};
    }
    @Test void disabledByDefaultNeedsNoSecretPolicyOrDatabase() {
        context(app("PAPER", true, true)).run(c -> {
            assertThat(c).hasNotFailed().doesNotHaveBean(PaperApprovalCallback.class)
                    .doesNotHaveBean(PaperApprovalHttp.BoundedTransport.class);
            verifyNoInteractions(source);
        });
    }
    @Test void explicitOptInConstructsOnlyReviewCallbackWithoutDatabaseCalls() throws Exception {
        context(app("PAPER", true, true)).withPropertyValues(settings()).run(c -> {
            assertThat(c).hasNotFailed().hasSingleBean(PaperApprovalCallback.class).hasSingleBean(DataSource.class);
            assertThat(c).doesNotHaveBean(PaperLedgerStore.class).doesNotHaveBean(PaperApprovalDelivery.class);
            verifyNoInteractions(source);
        });
    }
    @Test void everyRequiredSettingIsMandatory() throws Exception {
        var all = settings();
        for (int i = 1; i < all.length; i++) {
            var subset = new ArrayList<>(List.of(all)); subset.remove(i);
            context(app("PAPER", true, true)).withPropertyValues(subset.toArray(String[]::new))
                    .run(c -> assertThat(c).hasFailed());
        }
        verifyNoInteractions(source);
    }
    @ParameterizedTest @ValueSource(strings={"LIVE", "telegram-disabled", "upstox-disabled"})
    void rejectsUnsafeApplicationMode(String state) throws Exception {
        context(app(state.equals("LIVE") ? "LIVE" : "PAPER", !state.equals("telegram-disabled"), !state.equals("upstox-disabled")))
                .withPropertyValues(settings()).run(c -> assertThat(c).hasFailed());
        verifyNoInteractions(source);
    }
    @ParameterizedTest @ValueSource(strings={"host=example.com", "activation=LIVE", "transport=anything", "database-oid=0",
            "max-quote-age-millis=0", "max-proposal-lifetime-seconds=601", "max-quantity=-1", "max-slippage-bps=10001"})
    void invalidPolicyOrTargetFailsBeforeAnyConnection(String setting) throws Exception {
        context(app("PAPER", true, true)).withPropertyValues(settings())
                .withPropertyValues("marketbrain.paper.review." + setting).run(c -> assertThat(c).hasFailed());
        verifyNoInteractions(source);
    }
    @ParameterizedTest @ValueSource(strings={"", "\n", "\r\n"})
    void boundedCredentialFormatReturnsFreshBuffers(String suffix) throws Exception {
        Path file = directory.resolve("secret"); Files.writeString(file, "ab".repeat(32) + suffix);
        char[] a = PaperReviewWiring.readCredential(file), b = PaperReviewWiring.readCredential(file);
        assertArrayEquals(a, b); assertNotSame(a, b);
        Files.writeString(file, "cd".repeat(32));
        assertEquals("cd".repeat(32), new String(PaperReviewWiring.readCredential(file)));
    }
    @ParameterizedTest @ValueSource(strings={"short", "g", " ", "\n\n", "\u0000"})
    void malformedCredentialsAreSanitized(String bad) throws Exception {
        Path file = directory.resolve("do-not-disclose-this-path");
        Files.writeString(file, bad.length() == 1 ? bad.repeat(64) : "ab".repeat(32) + bad);
        var failure = assertThrows(IllegalArgumentException.class, () -> PaperReviewWiring.readCredential(file));
        assertNull(failure.getCause()); assertFalse(failure.toString().contains(file.toString()));
    }
    @Test void missingRelativeDirectoryAndOversizedSecretsRejected() throws Exception {
        for (Path file : List.of(Path.of("relative"), directory, directory.resolve("missing")))
            assertThrows(IllegalArgumentException.class, () -> PaperReviewWiring.readCredential(file));
        Path file = directory.resolve("large"); Files.writeString(file, "ab".repeat(10000));
        assertThrows(IllegalArgumentException.class, () -> PaperReviewWiring.readCredential(file));
    }
    @Test void factoryNeverDialsOrReadsSecretsUntilAnAuthorizedCallback() throws Exception {
        var target = new PaperWriterConnector.Target("127.0.0.1", 1, "unused", 1,
                PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE, null);
        var callback = PaperReviewWiring.callback(target, directory.resolve("missing"), p -> {throw new AssertionError();},
                Clock.systemUTC(), PaperApprovalVerification.POLICY);
        assertThrows(IllegalArgumentException.class, () -> callback.handle("x", 1, 1, "group", "mbp:" + "a".repeat(43)));
        assertThrows(IllegalArgumentException.class, () -> callback.handle("x", 1, 1, "private", "bad"));
    }
}
