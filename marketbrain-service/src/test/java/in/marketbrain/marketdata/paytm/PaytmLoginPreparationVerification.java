package in.marketbrain.marketdata.paytm;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/** Native JDK 21+ synthetic verifier, also exercised by JUnit. No external dependencies or I/O. */
public final class PaytmLoginPreparationVerification {
    private static final String TOKEN = "SYNTHETIC_TOKEN";
    public record Check(String name, boolean passed, long elapsedNanos) {}
    private static final class TestClock extends Clock {
        private Instant now = Instant.parse("2026-01-01T00:00:00Z");
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
    private static String query(PaytmLoginPreparation.Challenge c) { return "state=" + c.state() + "&requestToken=" + TOKEN; }
    private static void require(boolean condition) { if (!condition) throw new AssertionError("Synthetic assertion failed"); }
    private static void rejects(Runnable action) {
        try { action.run(); } catch (IllegalArgumentException e) {
            require("PAYTM_CALLBACK_REJECTED".equals(e.getMessage())); return;
        }
        throw new AssertionError("Expected rejection");
    }
    private static void check(List<Check> checks, String name, Runnable action) {
        long start = System.nanoTime();
        boolean passed = false;
        try { action.run(); passed = true; } catch (Exception | AssertionError ignored) { /* Synthetic details only. */ }
        checks.add(new Check(name, passed, System.nanoTime() - start));
    }
    public static List<Check> run() {
        List<Check> results = new ArrayList<>();
        check(results, "challenge_entropy_shape_and_redaction", () -> {
            var c = new PaytmLoginPreparation(new TestClock()).begin();
            require(c.state().matches("[A-Za-z0-9_-]{43}") && c.browserBinding().matches("[A-Za-z0-9_-]{43}"));
            require(!c.state().equals(c.browserBinding()) && !c.toString().contains(c.state()));
        });
        check(results, "fixed_https_login_origin", () -> {
            var c = new PaytmLoginPreparation(new TestClock()).begin();
            var uri = PaytmLoginPreparation.loginUri("SYNTHETIC_KEY", c.state());
            require(uri.toString().equals("https://login.paytmmoney.com/merchant-login?apiKey=SYNTHETIC_KEY&state=" + c.state()));
        });
        for (String key : List.of("", "key&state=evil", "https://evil.invalid", "a\r\nb", "a".repeat(257))) {
            int index = results.size();
            check(results, "invalid_login_key_" + index, () -> rejects(() -> PaytmLoginPreparation.loginUri(key, "a".repeat(43))));
        }
        check(results, "invalid_login_state", () -> rejects(() -> PaytmLoginPreparation.loginUri("SYNTHETIC_KEY", "bad")));
        check(results, "valid_then_replay_denied", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
            p.validateAndDiscard(query(c), c.browserBinding());
            rejects(() -> p.validateAndDiscard(query(c), c.browserBinding()));
        });
        check(results, "wrong_browser_does_not_consume_valid_challenge", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var a = p.begin(); var b = p.begin();
            rejects(() -> p.validateAndDiscard(query(a), b.browserBinding()));
            p.validateAndDiscard(query(a), a.browserBinding());
        });
        check(results, "missing_browser_denied", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
            rejects(() -> p.validateAndDiscard(query(c), null));
        });
        check(results, "unknown_state_denied", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
            rejects(() -> p.validateAndDiscard("state=" + "x".repeat(43) + "&requestToken=" + TOKEN, c.browserBinding()));
        });
        check(results, "expiry_boundary_denied", () -> {
            var clock = new TestClock(); var p = new PaytmLoginPreparation(clock); var c = p.begin();
            clock.now = c.expiresAt(); rejects(() -> p.validateAndDiscard(query(c), c.browserBinding()));
        });
        check(results, "before_expiry_allowed", () -> {
            var clock = new TestClock(); var p = new PaytmLoginPreparation(clock); var c = p.begin();
            clock.now = c.expiresAt().minusNanos(1); p.validateAndDiscard(query(c), c.browserBinding());
        });
        check(results, "clock_rollback_denied", () -> {
            var clock = new TestClock(); var p = new PaytmLoginPreparation(clock); var c = p.begin();
            clock.now = clock.now.minusSeconds(1); rejects(() -> p.validateAndDiscard(query(c), c.browserBinding()));
        });
        check(results, "restart_invalidates_challenges", () -> {
            var c = new PaytmLoginPreparation(new TestClock()).begin();
            rejects(() -> new PaytmLoginPreparation(new TestClock()).validateAndDiscard(query(c), c.browserBinding()));
        });
        check(results, "bounded_capacity_and_expired_cleanup", () -> {
            var clock = new TestClock(); var p = new PaytmLoginPreparation(clock); var states = new HashSet<String>();
            for (int i = 0; i < PaytmLoginPreparation.CAPACITY; i++) states.add(p.begin().state());
            require(states.size() == PaytmLoginPreparation.CAPACITY); rejects(p::begin);
            clock.now = clock.now.plus(PaytmLoginPreparation.LIFETIME); p.begin();
        });
        List<String> invalidQueries = List.of("", "state=one", "state=one&state=two", "state=one&%73tate=two",
                "state=one&request_token=wrong_alias", "state=one&requestToken=", "state=one&requestToken=%XX",
                "state=one&requestToken=token&extra=field", "state=one&requestToken=token&", "=one&requestToken=token",
                "state=one&error=denied", "x".repeat(8193));
        for (int i = 0; i < invalidQueries.size(); i++) {
            String invalid = invalidQueries.get(i);
            check(results, "malformed_query_" + i, () -> {
                var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
                rejects(() -> p.validateAndDiscard(invalid, c.browserBinding()));
            });
        }
        check(results, "null_query_denied", () -> rejects(() -> new PaytmLoginPreparation(new TestClock()).validateAndDiscard(null, null)));
        for (String token : List.of("", "a".repeat(4097), "a%0Db", "a%00b", "a+b")) {
            int index = results.size();
            check(results, "invalid_token_" + index, () -> {
                var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
                rejects(() -> p.validateAndDiscard("state=" + c.state() + "&requestToken=" + token, c.browserBinding()));
            });
        }
        check(results, "duplicate_token_denied", () -> rejects(() -> PaytmLoginPreparation.parse("requestToken=a&requestToken=b")));
        check(results, "encoded_key_and_reversed_order", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
            p.validateAndDiscard("requestToken=" + TOKEN + "&%73tate=" + c.state(), c.browserBinding());
        });
        check(results, "concurrent_callback_has_one_winner", () -> {
            var p = new PaytmLoginPreparation(new TestClock()); var c = p.begin();
            try (var pool = Executors.newFixedThreadPool(8)) {
                var tasks = new ArrayList<java.util.concurrent.Callable<Integer>>();
                for (int i = 0; i < 8; i++) tasks.add(() -> {
                    try { p.validateAndDiscard(query(c), c.browserBinding()); return 1; }
                    catch (IllegalArgumentException e) { return 0; }
                });
                int winners = 0;
                for (var future : pool.invokeAll(tasks, 5, TimeUnit.SECONDS)) winners += future.get();
                require(winners == 1);
            } catch (Exception e) { throw new AssertionError("Concurrency check failed"); }
        });
        return List.copyOf(results);
    }
    public static void main(String[] args) {
        if (args.length != 1 || !"--synthetic-only".equals(args[0])) throw new IllegalArgumentException("Synthetic mode required");
        var checks = run();
        long failures = checks.stream().filter(c -> !c.passed()).count();
        String entries = checks.stream().map(c -> "{\"name\":\"" + c.name() + "\",\"passed\":" + c.passed()
                + ",\"elapsedNanos\":" + c.elapsedNanos() + "}").collect(java.util.stream.Collectors.joining(","));
        System.out.println("{\"version\":\"PAYTM_LOGIN_CORE_V1\",\"syntheticOnly\":true,\"checkCount\":" + checks.size()
                + ",\"failedCheckCount\":" + failures + ",\"checks\":[" + entries + "]}");
        if (failures != 0) System.exit(1);
    }
}
