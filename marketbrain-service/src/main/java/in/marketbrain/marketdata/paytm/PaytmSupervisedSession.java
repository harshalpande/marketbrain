package in.marketbrain.marketdata.paytm;

import java.net.URI;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

/** One supervised owner session. No background work, persistence, health latch or trading. */
public final class PaytmSupervisedSession implements AutoCloseable {
    interface Broker {
        String exchange(String key, String secret, String requestToken);
        void verifyRead(String readToken);
        default com.fasterxml.jackson.databind.JsonNode quote(String readToken, int securityId) { throw new IllegalStateException("PAYTM_QUOTE_UNAVAILABLE"); }
    }
    private final Broker broker;
    private final java.util.function.Function<Instant, Clock> clockFactory;
    private Clock clock;
    private PaytmLoginPreparation preparation;
    private PaytmLoginPreparation.Challenge challenge;
    private String launchCode, key, secret, readToken;
    private String state = "LOCKED";
    private String failure = "NONE";
    private int quoteCalls;
    private Instant nextQuote;
    public PaytmSupervisedSession(PaytmSupervisedClient client) {
        this(new Broker() {
            public String exchange(String k, String s, String t) { return client.exchange(k,s,t); }
            public void verifyRead(String t) { client.verifyRead(t); }
            public com.fasterxml.jackson.databind.JsonNode quote(String t, int id) { return client.quote(t,id); }
        }, instant -> new PaytmSupervisedClock(instant, Duration.ofMinutes(20)));
    }
    PaytmSupervisedSession(Broker broker, java.util.function.Function<Instant, Clock> clockFactory) {
        this.broker = broker; this.clockFactory = clockFactory;
    }
    public synchronized String start(String apiKey, String apiSecret, long vpsEpochMillis) {
        if (apiKey == null || !apiKey.matches("[A-Za-z0-9_-]{1,256}") || apiSecret == null
                || !apiSecret.matches("[A-Za-z0-9_./+=-]{1,4096}")
                || vpsEpochMillis < 1577836800000L || vpsEpochMillis > 4102444800000L)
            throw new IllegalArgumentException("SUPERVISED_INPUT_INVALID");
        close();
        failure = "NONE";
        clock = clockFactory.apply(Instant.ofEpochMilli(vpsEpochMillis));
        preparation = new PaytmLoginPreparation(clock);
        challenge = preparation.begin();
        launchCode = challenge.state();
        key = apiKey; secret = apiSecret; state = "AWAITING_BROWSER";
        return "http://127.0.0.1:8080/paytm/supervised/browser?code=" + launchCode;
    }
    public record BrowserStart(URI location, String binding) {
        @Override public String toString() { return "BrowserStart[REDACTED]"; }
    }
    public synchronized BrowserStart browser(String code) {
        alive();
        if (!"AWAITING_BROWSER".equals(state) || code == null || launchCode == null
                || !MessageDigest.isEqual(launchCode.getBytes(StandardCharsets.UTF_8), code.getBytes(StandardCharsets.UTF_8)))
            throw new IllegalArgumentException("SUPERVISED_BROWSER_REJECTED");
        launchCode = null; state = "AWAITING_CALLBACK";
        return new BrowserStart(PaytmLoginPreparation.loginUri(key, challenge.state()), challenge.browserBinding());
    }
    public synchronized void callback(String query, String binding) {
        alive();
        if (!"AWAITING_CALLBACK".equals(state)) throw new IllegalArgumentException("SUPERVISED_CALLBACK_REJECTED");
        String requestToken;
        try {
            requestToken = preparation.consume(query, binding);
        } catch (IllegalArgumentException e) {
            // End the failing owner's attempt promptly; unrelated browser cookies cannot cancel it.
            if (binding != null && challenge != null && MessageDigest.isEqual(
                    challenge.browserBinding().getBytes(StandardCharsets.UTF_8), binding.getBytes(StandardCharsets.UTF_8))) {
                failure = "PAYTM_CALLBACK_REJECTED";
                close();
            }
            throw e;
        }
        try {
            readToken = broker.exchange(key, secret, requestToken);
            alive();
            broker.verifyRead(readToken);
            alive(); state = "READ_ACCESS_VERIFIED";
        } catch (RuntimeException e) {
            failure = e.getMessage() != null && e.getMessage().matches("(PAYTM|SUPERVISED)_[A-Z0-9_]{1,80}") ? e.getMessage() : "SUPERVISED_EXCHANGE_FAILED";
            close(); throw e;
        }
        finally { key = null; secret = null; challenge = null; preparation = null; }
    }
    public synchronized Map<String,Object> status() {
        if (clock != null) { try { alive(); } catch (IllegalStateException ignored) { } }
        return Map.of("status", state, "readAccessVerified", "READ_ACCESS_VERIFIED".equals(state),
                "clockSource", "VPS_ANCHORED_MONOTONIC", "vpsAccuracyAssumed", true,
                "windowsClockGate", false, "ordersEnabled", false, "failure", failure);
    }
    public synchronized Map<String,Object> quote(int securityId) {
        alive();
        if (!"READ_ACCESS_VERIFIED".equals(state)) throw new IllegalStateException("PAYTM_READ_ACCESS_REQUIRED");
        if(securityId<1 || securityId>99999999) throw new IllegalArgumentException("PAYTM_SECURITY_ID_INVALID");
        Instant now=clock.instant();
        if(quoteCalls>=3 || (nextQuote!=null && now.isBefore(nextQuote))) throw new IllegalStateException("PAYTM_QUOTE_LIMIT");
        quoteCalls++; nextQuote=now.plusSeconds(5);
        try {
            var reply=broker.quote(readToken,securityId);
            alive();
            return PaytmQuoteProbe.assess(reply,securityId,clock.instant());
        } catch(RuntimeException e) {
            failure=e.getMessage()!=null && e.getMessage().matches("(PAYTM|SUPERVISED)_[A-Z0-9_]{1,80}")?e.getMessage():"PAYTM_QUOTE_FAILED";
            close();throw new IllegalStateException(failure);
        }
    }
    private void alive() {
        if (clock == null) throw new IllegalStateException("SUPERVISED_SESSION_LOCKED");
        try { clock.instant(); } catch (RuntimeException e) { failure="SUPERVISED_SESSION_EXPIRED";close(); throw new IllegalStateException("SUPERVISED_SESSION_EXPIRED"); }
    }
    @Override public synchronized void close() {
        quoteCalls=0;nextQuote=null;
        key = null; secret = null; readToken = null; launchCode = null; challenge = null; preparation = null; clock = null; state = "LOCKED";
    }
}
