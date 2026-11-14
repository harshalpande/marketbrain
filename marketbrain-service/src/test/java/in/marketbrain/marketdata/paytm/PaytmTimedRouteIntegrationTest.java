package in.marketbrain.marketdata.paytm;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import in.marketbrain.configuration.MarketBrainProperties;
import static org.assertj.core.api.Assertions.*;

class PaytmTimedRouteIntegrationTest {
    private static final PaytmGatewayTransport.Observation TLS = new PaytmGatewayTransport.Observation("TLS_RESPONSE",503,true,"NONE");
    private static void health(PaytmApplicationRoute r,long seq) {
        assertThat(r.observeHealth(new PaytmDiagnosticTimingGuard.Health(r.status().bootId(),seq,true,true,0,0))).isTrue();
    }
    @Test void completeGuardRegressionSuite() { PaytmDiagnosticTimingVerification.main(new String[0]); }
    @Test void productionSpringBeanFailsClosedWithoutHealthProvider() {
        new ApplicationContextRunner().withBean(MarketBrainProperties.class,()->PaytmApplicationRouteTest.properties(false,""))
            .withUserConfiguration(PaytmApplicationRoute.class,PaytmApplicationRouteController.class)
            .run(c->{assertThat(c).hasNotFailed();var r=c.getBean(PaytmApplicationRoute.class);
                assertThat(r.arm().status()).isEqualTo("TIMING_BLOCKED");
                assertThat(r.head().tlsVerified()).isFalse();assertThat(r.status().state()).isEqualTo("LOCKED");});
    }
    @Test void missingStaleAndUnhealthyEvidencePreventTransport() {
        var n=new AtomicLong();var w=new AtomicLong();var calls=new AtomicInteger();
        var r=new PaytmApplicationRoute(true,n::get,w::get,()->{calls.incrementAndGet();return TLS;});
        r.arm();r.head();assertThat(calls.get()).isZero();
        health(r,0);r.arm();n.set(30_000_000_000L);w.set(30000);r.head();assertThat(calls.get()).isZero();
        r.observeHealth(new PaytmDiagnosticTimingGuard.Health(r.status().bootId(),1,true,false,0,0));
        r.arm();r.head();assertThat(calls.get()).isZero();
    }
    @Test void clockJumpsBlockBeforeTransport() {
        for(long jump:new long[]{6000,-6000}) {
            var n=new AtomicLong();var w=new AtomicLong();var calls=new AtomicInteger();
            var r=new PaytmApplicationRoute(true,n::get,w::get,()->{calls.incrementAndGet();return TLS;});
            health(r,0);r.arm();w.set(jump);
            assertThat(r.head().failureType()).isEqualTo("WALL_CLOCK_DISCONTINUITY");assertThat(calls.get()).isZero();
        }
    }
    @Test void clockJumpDuringTransportDiscardsResponseAndLocks() {
        var n=new AtomicLong();var w=new AtomicLong();var calls=new AtomicInteger();
        var r=new PaytmApplicationRoute(true,n::get,w::get,()->{calls.incrementAndGet();w.set(6000);return TLS;});
        health(r,0);r.arm();var result=r.head();
        assertThat(result.status()).isEqualTo("TIMING_BLOCKED");assertThat(result.httpStatus()).isZero();
        assertThat(result.tlsVerified()).isFalse();assertThat(result.state()).isEqualTo("LOCKED");
        r.head();assertThat(calls.get()).isEqualTo(1);
    }
    @Test void healthExpiresDuringTransportDiscardsResponse() {
        var n=new AtomicLong();var w=new AtomicLong();
        var r=new PaytmApplicationRoute(true,n::get,w::get,()->{n.set(30_000_000_000L);w.set(30000);return TLS;});
        health(r,0);r.arm();assertThat(r.head().status()).isEqualTo("TIMING_BLOCKED");
    }
    @Test void restartCannotReuseEvidenceOrArmAutomatically() {
        var first=new PaytmApplicationRoute(true,()->0L,()->0L,()->TLS);health(first,0);first.arm();
        var second=new PaytmApplicationRoute(true,()->0L,()->0L,()->TLS);
        assertThat(second.observeHealth(new PaytmDiagnosticTimingGuard.Health(first.status().bootId(),1,true,true,0,0))).isFalse();
        assertThat(second.arm().status()).isEqualTo("TIMING_BLOCKED");assertThat(second.head().tlsVerified()).isFalse();
    }
    @Test void freshHealthAfterFailureDoesNotRearm() {
        var n=new AtomicLong();var w=new AtomicLong();var calls=new AtomicInteger();
        var r=new PaytmApplicationRoute(true,n::get,w::get,()->{calls.incrementAndGet();return TLS;});
        health(r,0);r.arm();w.set(6000);r.head();health(r,1);r.head();assertThat(calls.get()).isZero();
        r.arm();assertThat(r.head().tlsVerified()).isTrue();assertThat(calls.get()).isEqualTo(1);
    }
    @Test void healthRefreshDuringRequestCannotRestoreRevokedLease() {
        var n=new AtomicLong();var w=new AtomicLong();
        var holder=new java.util.concurrent.atomic.AtomicReference<PaytmApplicationRoute>();
        var r=new PaytmApplicationRoute(true,n::get,w::get,()->{
            w.set(6000);health(holder.get(),1);return TLS;
        });holder.set(r);health(r,0);r.arm();
        assertThat(r.head().status()).isEqualTo("TIMING_BLOCKED");
        assertThat(r.status().state()).isEqualTo("LOCKED");
    }
}
