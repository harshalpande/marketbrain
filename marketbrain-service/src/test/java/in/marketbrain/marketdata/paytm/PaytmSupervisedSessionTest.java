package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
import java.time.*;
import java.net.URI;
import java.util.concurrent.atomic.AtomicLong;

class PaytmSupervisedSessionTest {
    private final AtomicLong ticks = new AtomicLong();
    private final Instant vps = Instant.parse("2026-11-20T00:00:00Z");
    private int exchanges, reads, quotes;
    private boolean fail;
    private boolean expireDuringQuote;
    private PaytmSupervisedSession create() {
        return new PaytmSupervisedSession(new PaytmSupervisedSession.Broker() {
            public String exchange(String k, String s, String t) { exchanges++; if(fail) throw new IllegalStateException("PAYTM_HTTP_401"); return "read-token"; }
            public void verifyRead(String t) { assertThat(t).isEqualTo("read-token"); reads++; }
            public com.fasterxml.jackson.databind.JsonNode quote(String t,int id) {
                assertThat(t).isEqualTo("read-token");quotes++;
                if(fail) throw new IllegalStateException("PAYTM_HTTP_429");
                if(expireDuringQuote)ticks.set(Duration.ofMinutes(20).toNanos());
                return PaytmQuoteProbeTest.reply(0);
            }
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
    private void login(PaytmSupervisedSession session) {
        var url=session.start("key","secret",vps.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        session.callback("state="+browser.location().getQuery().split("state=")[1]+"&requestToken=test",browser.binding());
    }
    @Test void reviewClockRequiresAuthenticatedLiveAnchor(){
        var session=create();assertThatThrownBy(session::reviewInstant).hasMessage("SUPERVISED_SESSION_LOCKED");
        session.start("key","secret",vps.toEpochMilli());assertThatThrownBy(session::reviewInstant).hasMessage("PAYTM_READ_ACCESS_REQUIRED");
        session.close();login(session);ticks.set(Duration.ofSeconds(2).toNanos());assertThat(session.reviewInstant()).isEqualTo(vps.plusSeconds(2));
        ticks.set(Duration.ofMinutes(20).toNanos());assertThatThrownBy(session::reviewInstant).hasMessage("SUPERVISED_SESSION_EXPIRED");
        assertThatThrownBy(session::reviewInstant).hasMessage("SUPERVISED_SESSION_LOCKED");
    }
    @Test void optInReplayConsumesSameCallbackOnlyOnceAndDoesNotRetainIt(){
        var session=create();
        var url=session.start("key","secret",vps.toEpochMilli(),true);
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        var query="success=true&state="+browser.location().getQuery().split("state=")[1]+"&requestToken=private-value";
        session.completeCallback(query,browser.binding());
        assertThat(session.status().get("callbackReplay")).isEqualTo(java.util.Map.of("requested",true,"verified",true,"exchangeAttempts",1));
        assertThat(exchanges).isEqualTo(1);assertThat(reads).isEqualTo(1);
        assertThat(session.status().get("readAccessVerified")).isEqualTo(true);
        assertThat(session.status().toString()).doesNotContain("private-value",browser.binding());
        assertThatThrownBy(()->session.completeCallback(query,browser.binding())).hasMessage("SUPERVISED_CALLBACK_REJECTED");
        assertThat(exchanges).isEqualTo(1);
        session.close();session.start("key","secret",vps.toEpochMilli());
        assertThat(session.status().get("callbackReplay")).isEqualTo(java.util.Map.of("requested",false,"verified",false,"exchangeAttempts",0));
    }
    @Test void replayProbeCannotReportSuccessWhenProviderReadFails(){
        var session=create();fail=true;
        var url=session.start("key","secret",vps.toEpochMilli(),true);
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        var query="success=true&state="+browser.location().getQuery().split("state=")[1]+"&requestToken=test";
        assertThatThrownBy(()->session.completeCallback(query,browser.binding())).hasMessage("PAYTM_HTTP_401");
        assertThat(session.status().get("callbackReplay")).isEqualTo(java.util.Map.of("requested",true,"verified",false,"exchangeAttempts",1));
        assertThat(session.status().get("status")).isEqualTo("LOCKED");
    }
    @Test void quoteRequiresLoginIsBoundedAndStopsOnProviderError() {
        var session=create();
        assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_LOCKED");
        login(session);
        session.quote(3456);
        assertThatThrownBy(()->session.quote(3456)).hasMessage("PAYTM_QUOTE_LIMIT");
        for(int i=1;i<3;i++){ticks.set(Duration.ofSeconds(i*5).toNanos());session.quote(3456);}
        ticks.set(Duration.ofSeconds(15).toNanos());
        assertThatThrownBy(()->session.quote(3456)).hasMessage("PAYTM_QUOTE_LIMIT");
        assertThat(quotes).isEqualTo(3);
        session.close();login(session);fail=true;
        assertThatThrownBy(()->session.quote(3456)).hasMessage("PAYTM_HTTP_429");
        assertThat(session.status()).containsEntry("status","LOCKED");
        assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_LOCKED");
        assertThat(quotes).isEqualTo(4);
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
    @Test void authenticatedSessionExpiryBlocksReadsUntilFreshLogin(){
        var session=create();login(session);
        ticks.set(Duration.ofMinutes(20).toNanos());
        assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_EXPIRED");
        assertThat(quotes).isZero();
        assertThat(session.status()).containsEntry("status","LOCKED").containsEntry("failure","SUPERVISED_SESSION_EXPIRED");
        login(session);session.quote(3456);
        assertThat(quotes).isEqualTo(1);assertThat(session.status()).containsEntry("failure","NONE");
    }
    @Test void responseArrivingAfterSessionExpiryCannotBeUsed(){
        var session=create();login(session);expireDuringQuote=true;
        assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_EXPIRED");
    }
    @Test void oldCallbackCannotReplaceNewOwnerChallenge(){
        var session=create();var url=session.start("key","secret",vps.toEpochMilli());
        var old=session.browser(URI.create(url).getQuery().substring(5));
        var oldQuery="state="+old.location().getQuery().split("state=")[1]+"&requestToken=old";
        var next=session.start("key","secret",vps.toEpochMilli());
        var current=session.browser(URI.create(next).getQuery().substring(5));
        assertThatThrownBy(()->session.callback(oldQuery,old.binding())).isInstanceOf(IllegalArgumentException.class);
        assertThat(exchanges).isZero();assertThat(session.status()).containsEntry("status","AWAITING_CALLBACK");
        session.callback("state="+current.location().getQuery().split("state=")[1]+"&requestToken=new",current.binding());
        assertThat(exchanges).isEqualTo(1);
    }
    @Test void newInstanceDoesNotInheritAuthenticatedSession(){
        var before=create();login(before);
        var after=create();assertThatThrownBy(()->after.quote(3456)).hasMessage("SUPERVISED_SESSION_LOCKED");
        assertThat(quotes).isZero();before.close();
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
