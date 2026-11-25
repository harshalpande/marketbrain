package in.marketbrain.paper;

import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import java.time.Clock;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaperPublisherConfigurationTest {
    static class Fixture extends PaperPublisherConfiguration {
        @Override @Bean PaperRuntimeControlServer paperPublisherControlServer(PaperPublisherRuntime runtime){return mock(PaperRuntimeControlServer.class);}
    }
    final PaytmPaperReviewAdapter quotes=mock(PaytmPaperReviewAdapter.class);
    final PaperApprovalHttp.BoundedTransport transport=mock(PaperApprovalHttp.BoundedTransport.class);
    ApplicationContextRunner enabled() {
        when(quotes.clock()).thenReturn(Clock.systemUTC());
        var app=new MarketBrainProperties("PAPER",null,null,null,null,null,new MarketBrainProperties.Telegram(true,"123:synthetic-never-sent","SYNTHETIC_PAIR_CODE",20,1000,false));
        var target=new PaperWriterConnector.Target("localhost",5432,"marketbrain",42,PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null);
        return new ApplicationContextRunner().withUserConfiguration(Fixture.class)
            .withBean(MarketBrainProperties.class,()->app)
            .withBean(PaperTelegramReviewConfiguration.Settings.class,()->new PaperTelegramReviewConfiguration.Settings(target,null,PaperReviewTestPolicy.paytmPolicy(),true))
            .withBean(PaperApprovalCallback.class,()->mock(PaperApprovalCallback.class))
            .withBean(PaytmPaperReviewAdapter.class,()->quotes).withBean(PaperApprovalHttp.BoundedTransport.class,()->transport)
            .withPropertyValues("marketbrain.paper.publisher.enabled=true","marketbrain.paper.publisher.activation=REVIEW_ONLY",
                "marketbrain.paper.publisher.credential-mode=PROCESS_MEMORY","marketbrain.paper.approval-key-file="+java.nio.file.Path.of("existing-key").toAbsolutePath());
    }
    @Test void defaultOffNeedsNoDependenciesOrSocket() {
        new ApplicationContextRunner().withUserConfiguration(PaperPublisherConfiguration.class).run(c->
            assertThat(c).hasNotFailed().doesNotHaveBean(PaperPublisherRuntime.class).doesNotHaveBean(PaperRuntimeControlServer.class));
    }
    @Test void enabledWithoutReviewDependenciesFailsClosed() {
        new ApplicationContextRunner().withUserConfiguration(PaperPublisherConfiguration.class)
            .withPropertyValues("marketbrain.paper.publisher.enabled=true").run(c->assertThat(c).hasFailed());
    }
    @ParameterizedTest @ValueSource(strings={"LIVE","FILE","UPSTOX","NO_TELEGRAM"})
    void rejectsWrongExecutionCredentialProviderOrMessaging(String bad) {
        var env=new org.springframework.mock.env.MockEnvironment().withProperty("marketbrain.paper.publisher.activation","REVIEW_ONLY")
            .withProperty("marketbrain.paper.publisher.credential-mode","PROCESS_MEMORY");
        var app=new MarketBrainProperties(bad.equals("LIVE")?"LIVE":"PAPER",null,null,null,null,null,
            new MarketBrainProperties.Telegram(!bad.equals("NO_TELEGRAM"),"123:synthetic-never-sent","SYNTHETIC_PAIR_CODE",20,1000,false));
        var target=new PaperWriterConnector.Target("localhost",5432,"marketbrain",42,PaperWriterConnector.Transport.PRIVATE_SAME_MACHINE,null);
        var policy=PaperReviewTestPolicy.paytmPolicy();
        if(bad.equals("UPSTOX"))policy=new PaperApprovalReview.PolicyVersion(policy.id(),"UPSTOX",policy.limits(),policy.maxProposalLifetime());
        var settings=new PaperTelegramReviewConfiguration.Settings(target,null,policy,!bad.equals("FILE"));
        assertThrows(IllegalStateException.class,()->new PaperPublisherConfiguration().paperPublisherRuntime(env,app,settings,mock(PaperApprovalCallback.class),quotes,transport));
        verifyNoInteractions(quotes,transport);
    }
    @Test void validStartupRemainsLockedAndSendsNothing() {
        enabled().run(c->{assertThat(c).hasNotFailed().hasSingleBean(PaperPublisherRuntime.class);
            assertFalse(c.getBean(PaperPublisherRuntime.class).ready());
            assertThrows(PaperRuntimeCredential.Locked.class,()->c.getBean(PaperPublisherRuntime.class).open());
            verifyNoInteractions(transport);verify(quotes,never()).reference(anyString());});
    }
    @ParameterizedTest @ValueSource(strings={"publisher.activation=LIVE","publisher.credential-mode=FILE","publisher.credential-file=anything","approval-key-file=relative"})
    void unsafeOptInFails(String property) throws Exception {enabled().withPropertyValues("marketbrain.paper."+property).run(c->assertThat(c).hasFailed());verify(transport,never()).exchange(any());}
}
