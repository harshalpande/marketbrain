package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
import java.time.*;
import java.net.URI;
import java.util.concurrent.atomic.AtomicLong;

class PaytmSupervisedSessionTest {
    private final AtomicLong ticks = new AtomicLong();
    private final Instant vps = Instant.parse("2026-11-20T00:00:00Z");
    private int exchanges, reads;
    private boolean fail;
    private PaytmSupervisedSession create() {
        return new PaytmSupervisedSession(new PaytmSupervisedSession.Broker() {
            public String exchange(String k, String s, String t) { exchanges++; if(fail) throw new IllegalStateException("PAYTM_HTTP_401"); return "read-token"; }
            public void verifyRead(String t) { assertThat(t).isEqualTo("read-token"); reads++; }
        }, instant -> new PaytmSupervisedClock(instant,Duration.ofMinutes(20),ticks::get));
    }
    @Test void loginConsumesOnceAndLockClearsSession() {
        var session=create();
        String url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        String state=browser.location().getQuery().split("state=")[1];
        assertThatThrownBy(()->session.callback("state="+state+"&requestToken=test","a".repeat(43))).isInstanceOf(IllegalArgumentException.class);
        assertThat(exchanges).isZero();
        session.callback("state="+state+"&requestToken=test",browser.binding());
        assertThat(session.status().get("readAccessVerified")).isEqualTo(true);
        assertThat(exchanges).isEqualTo(1); assertThat(reads).isEqualTo(1);
        assertThatThrownBy(()->session.callback("state="+state+"&requestToken=test",browser.binding())).isInstanceOf(IllegalArgumentException.class);
        session.close(); assertThat(session.status().get("status")).isEqualTo("LOCKED");
    }
    @Test void callbackExpiryUsesElapsedTimeNotHostWallClock() {
        var session=create();
        String url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        String state=browser.location().getQuery().split("state=")[1];
        ticks.set(Duration.ofMinutes(10).toNanos());
        assertThatThrownBy(()->session.callback("state="+state+"&requestToken=test",browser.binding())).isInstanceOf(IllegalArgumentException.class);
        assertThat(exchanges).isZero();
    }
    @Test void observedProviderSuccessFlagAcceptedOnce() {
        var session=create();
        var url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        var state=browser.location().getQuery().split("state=")[1];
        var query="success=true&requestToken=fixture-token&state="+state;
        session.callback(query,browser.binding());
        assertThat(session.status().get("readAccessVerified")).isEqualTo(true);
        assertThat(exchanges).isEqualTo(1); assertThat(reads).isEqualTo(1);
        assertThatThrownBy(()->session.callback(query,browser.binding())).isInstanceOf(IllegalArgumentException.class);
        assertThat(exchanges).isEqualTo(1);
    }
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings={"success=false", "success=TRUE", "success=", "success=true&success=false", "success=true&%73uccess=true", "other=true"})
    void malformedOrUnsuccessfulOwnerCallbackStopsWithoutBrokerCall(String prefix) {
        var session=create();
        var url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        var state=browser.location().getQuery().split("state=")[1];
        assertThatThrownBy(()->session.callback(prefix+"&requestToken=fixture&state="+state,browser.binding())).isInstanceOf(IllegalArgumentException.class);
        assertThat(exchanges).isZero(); assertThat(reads).isZero();
        assertThat(session.status().get("status")).isEqualTo("LOCKED");
        assertThat(session.status().get("failure")).isEqualTo("PAYTM_CALLBACK_REJECTED");
        // Retry creates a fresh state/cookie and clears the previous failed attempt.
        var next=session.start("key","secret",vps.toEpochMilli());
        var fresh=session.browser(URI.create(next).getQuery().substring(5));
        assertThat(session.status().get("failure")).isEqualTo("NONE");
        assertThat(fresh.binding()).isNotEqualTo(browser.binding());
        var newState=fresh.location().getQuery().split("state=")[1];
        assertThat(newState).isNotEqualTo(state);
        session.callback("state="+newState+"&success=true&requestToken=fixture",fresh.binding());
        assertThat(session.status().get("readAccessVerified")).isEqualTo(true);
    }
    @Test void providerFailureClearsCredentialsAndDoesNotRetry() {
        var session=create(); fail=true;
        String url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        String state=browser.location().getQuery().split("state=")[1];
        assertThatThrownBy(()->session.callback("state="+state+"&requestToken=test",browser.binding())).hasMessage("PAYTM_HTTP_401");
        assertThat(session.status().get("status")).isEqualTo("LOCKED"); assertThat(exchanges).isEqualTo(1); assertThat(reads).isZero();
    }
    @Test void restartAndTwentyMinuteExpiryRequireNewLogin() {
        var session=create(); session.start("key","secret",vps.toEpochMilli());
        ticks.set(Duration.ofMinutes(20).toNanos());
        assertThat(session.status().get("status")).isEqualTo("LOCKED");
        assertThat(create().status().get("status")).isEqualTo("LOCKED");
    }
    @Test void vpsAnchorAdvancesAndRejectsMonotonicRollback() {
        var clock=new PaytmSupervisedClock(vps,Duration.ofMinutes(20),ticks::get);
        ticks.set(Duration.ofSeconds(100).toNanos()); assertThat(clock.instant()).isEqualTo(vps.plusSeconds(100));
        ticks.set(-1); assertThatThrownBy(clock::instant).hasMessage("SUPERVISED_SESSION_EXPIRED");
    }
    @Test void clientAllowsOnlyTwoFixedHttpsDestinations() {
        assertThat(PaytmSupervisedClient.allowed(PaytmSupervisedClient.TOKEN)).isTrue();
        assertThat(PaytmSupervisedClient.allowed(URI.create("https://developer.paytmmoney.com/accounts/v1/user/details"))).isTrue();
        for(String target: new String[]{"https://developer.paytmmoney.com/orders/v1/place/regular", "http://developer.paytmmoney.com/accounts/v2/gettoken", "https://example.com/accounts/v2/gettoken", "https://developer.paytmmoney.com/accounts/v2/gettoken?x=1"})
            assertThat(PaytmSupervisedClient.allowed(URI.create(target))).isFalse();
    }
    @Test void oversizedReplyCancelledBeforeBufferGrowth() {
        var body=new PaytmSupervisedClient.BoundedBody();
        var cancelled=new java.util.concurrent.atomic.AtomicBoolean();
        body.onSubscribe(new java.util.concurrent.Flow.Subscription(){public void request(long n){} public void cancel(){cancelled.set(true);}});
        body.onNext(java.util.List.of(java.nio.ByteBuffer.allocate(262145)));
        assertThat(cancelled).isTrue(); assertThat(body.getBody().toCompletableFuture().isCompletedExceptionally()).isTrue();
    }
}
