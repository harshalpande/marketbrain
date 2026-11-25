package in.marketbrain.paper;

import in.marketbrain.marketdata.paytm.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.*;
import org.springframework.mock.env.MockEnvironment;
import javax.sql.DataSource;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPaytmReviewConfigurationTest {
    @Configuration(proxyBeanMethods=false)
    static class TestConfiguration extends PaperTelegramReviewConfiguration {
        @Override @Bean(destroyMethod="close")
        PaperRuntimeControlServer paperRuntimeControlServer(PaperRuntimeCredential credential) {
            return mock(PaperRuntimeControlServer.class);
        }
    }
    MockEnvironment env() {
        var env=new MockEnvironment();
        PaperRuntimeReviewVerification.properties().forEach((k,v)->env.setProperty(k,v.toString()));
        env.setProperty("marketbrain.paper.review.quote-provider","PAYTM");
        env.setProperty("marketbrain.paper.review.policy-id","PAPER_PAYTM_TEST_100S_V1");
        return env;
    }
    in.marketbrain.configuration.MarketBrainProperties app() {
        var old=PaperRuntimeReviewVerification.app();
        return new in.marketbrain.configuration.MarketBrainProperties("PAPER",null,null,null,null,null,old.telegram());
    }
    @Test void explicitPaytmRequiresNoUpstoxAndUsesLockedSessionClock() {
        var source=mock(DataSource.class);
        var session=new PaytmSupervisedController("x".repeat(40),"PAPER",false);
        new ApplicationContextRunner().withUserConfiguration(TestConfiguration.class)
            .withInitializer(c->c.getEnvironment().getPropertySources().addFirst(env().getPropertySources().get("mockProperties")))
            .withBean(DataSource.class,()->source)
            .withBean(in.marketbrain.configuration.MarketBrainProperties.class,this::app)
            .withPropertyValues("marketbrain.paytm-supervised.enabled=true")
            .withBean(PaytmSupervisedController.class,()->session)
            .run(c->{
                assertThat(c).hasNotFailed().hasSingleBean(PaperApprovalCallback.class).hasSingleBean(PaytmPaperReviewAdapter.class);
                assertThat(c).doesNotHaveBean(PaperApprovalDelivery.class).doesNotHaveBean(PaperLedgerStore.class);
                assertThrows(IllegalStateException.class,()->c.getBean(PaytmPaperReviewAdapter.class).clock().instant());
                assertFalse(c.getBean(PaperRuntimeCredential.class).ready());
                assertThrows(PaperRuntimeCredential.Locked.class,()->c.getBean(PaperApprovalCallback.class)
                    .handle("test",1,1,"private","mbp:"+"a".repeat(43)));
                verifyNoInteractions(source);
            });
    }
    @Test void missingSupervisedSessionFailsStartupWithoutFallback() {
        new ApplicationContextRunner().withUserConfiguration(TestConfiguration.class)
            .withInitializer(c->c.getEnvironment().getPropertySources().addFirst(env().getPropertySources().get("mockProperties")))
            .withBean(DataSource.class,()->mock(DataSource.class))
            .withBean(in.marketbrain.configuration.MarketBrainProperties.class,this::app)
            .run(c->assertThat(c).hasFailed());
    }
    @ParameterizedTest @ValueSource(strings={"quote-provider=OTHER","policy-id=PAPER_TELEGRAM_TEST_100S_V1",
        "max-quote-age-millis=16000","max-slippage-bps=51","max-quantity=2","max-order-notional-paise=500001",
        "max-proposal-lifetime-seconds=101","max-approvals=3","max-fills=2","credential-mode=FILE"})
    void refusesPolicyDrift(String setting) {
        var env=env();var parts=setting.split("=",2);env.setProperty("marketbrain.paper.review."+parts[0],parts[1]);
        assertThrows(IllegalStateException.class,()->new PaperTelegramReviewConfiguration().paperReviewSettings(env,app()));
    }
}
