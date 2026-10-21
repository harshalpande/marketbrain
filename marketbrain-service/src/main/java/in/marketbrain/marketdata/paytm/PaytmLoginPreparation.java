package in.marketbrain.marketdata.paytm;

import java.net.URI;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/** Disconnected login preparation. No HTTP client, credentials, token exchange or persistence. */
public final class PaytmLoginPreparation {
    public static final String CALLBACK = "http://127.0.0.1:8080/paytm/callback";
    public static final Duration LIFETIME = Duration.ofMinutes(10);
    public static final int CAPACITY = 8;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();
    private final Map<String, Pending> pending = new HashMap<>();

    public PaytmLoginPreparation(Clock clock) { this.clock = java.util.Objects.requireNonNull(clock); }

    public record Challenge(String state, String browserBinding, Instant expiresAt) {
        @Override public String toString() { return "PaytmChallenge[REDACTED]"; }
    }
    private record Pending(String binding, Instant issuedAt, Instant expiresAt) {}

    public synchronized Challenge begin() {
        Instant now = clock.instant();
        pending.values().removeIf(p -> !now.isBefore(p.expiresAt()) || now.isBefore(p.issuedAt()));
        if (pending.size() >= CAPACITY) throw rejected();
        String state;
        do { state = nonce(); } while (pending.containsKey(state));
        String binding = nonce();
        Instant expiry = now.plus(LIFETIME);
        pending.put(state, new Pending(binding, now, expiry));
        return new Challenge(state, binding, expiry);
    }

    /** Future login URL contract only; never called by the rehearsal controller. */
    public static URI loginUri(String apiKey, String state) {
        if (apiKey == null || !apiKey.matches("[A-Za-z0-9_-]{1,256}") || !validNonce(state)) throw rejected();
        return URI.create("https://login.paytmmoney.com/merchant-login?apiKey="
                + URLEncoder.encode(apiKey, StandardCharsets.UTF_8) + "&state=" + state);
    }

    /** Consumes the challenge once; the request token is NOT retained, exchanged or returned. */
    public synchronized void validateAndDiscard(String query, String browserBinding) {
        Map<String, String> fields = parse(query);
        String state = fields.get("state");
        String requestToken = fields.get("requestToken");
        if (!validNonce(state) || !validNonce(browserBinding) || requestToken == null
                || !requestToken.matches("[A-Za-z0-9_.=-]{1,4096}")) throw rejected();
        Pending value = pending.get(state);
        if (value == null || !MessageDigest.isEqual(value.binding().getBytes(StandardCharsets.US_ASCII),
                browserBinding.getBytes(StandardCharsets.US_ASCII))) throw rejected();
        Instant now = clock.instant();
        pending.remove(state);
        if (!now.isBefore(value.expiresAt()) || now.isBefore(value.issuedAt())) throw rejected();
    }

    static Map<String, String> parse(String query) {
        if (query == null || query.length() > 8192) throw rejected();
        Map<String, String> fields = new HashMap<>();
        String[] parts = query.split("&", -1);
        if (parts.length != 2) throw rejected();
        try {
            for (String part : parts) {
                int separator = part.indexOf('=');
                if (separator <= 0) throw rejected();
                String key = URLDecoder.decode(part.substring(0, separator), StandardCharsets.UTF_8);
                String value = URLDecoder.decode(part.substring(separator + 1), StandardCharsets.UTF_8);
                if (!(key.equals("state") || key.equals("requestToken")) || fields.putIfAbsent(key, value) != null)
                    throw rejected();
            }
        } catch (IllegalArgumentException e) { throw rejected(); }
        return fields;
    }

    private String nonce() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    private static boolean validNonce(String value) { return value != null && value.matches("[A-Za-z0-9_-]{43}"); }
    private static IllegalArgumentException rejected() { return new IllegalArgumentException("PAYTM_CALLBACK_REJECTED"); }
}
