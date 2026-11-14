package in.marketbrain.marketdata.paytm;

import java.util.UUID;
import java.util.function.LongSupplier;

/** Diagnostic-route timing policy. No broker, approval or order authority.
 * Constants are diagnostic test policy, not approved trading timing tolerances. */
public final class PaytmDiagnosticTimingGuard {
    public static final long HEALTH_TTL_NANOS = 30_000_000_000L;
    public static final long LEASE_NANOS = 100_000_000_000L;
    private final String bootId = UUID.randomUUID().toString();
    private final LongSupplier monotonic, wallMillis;
    private long sequence = -1, observedNano, observedWall, armedNano;
    private boolean healthy, leaseValid;
    private int remaining;
    private String reason = "NO_HEALTH_EVIDENCE";
    public PaytmDiagnosticTimingGuard(LongSupplier monotonic, LongSupplier wallMillis) {
        this.monotonic = java.util.Objects.requireNonNull(monotonic);
        this.wallMillis = java.util.Objects.requireNonNull(wallMillis);
    }
    public String bootId() { return bootId; }
    public record Health(String bootId, long sequence, boolean synchronizedClock,
                         boolean transportHealthy, double lowerOffsetSeconds, double upperOffsetSeconds) {}
    public record Decision(boolean diagnosticAllowed, String reason, int remainingRequests) {}
    public synchronized boolean observe(Health value) {
        if (value == null || !bootId.equals(value.bootId()) || value.sequence() <= sequence || value.sequence() < 0) {
            healthy = false; leaseValid = false; remaining = 0; reason = "EVIDENCE_IDENTITY_OR_REPLAY"; return false;
        }
        // A new observation cannot erase a detected discontinuity and retain the old lease.
        if (healthy) healthValid(monotonic.getAsLong());
        sequence = value.sequence(); observedNano = monotonic.getAsLong(); observedWall = wallMillis.getAsLong();
        healthy = value.synchronizedClock() && value.transportHealthy()
                && Double.isFinite(value.lowerOffsetSeconds()) && Double.isFinite(value.upperOffsetSeconds())
                && value.lowerOffsetSeconds() <= value.upperOffsetSeconds()
                && value.lowerOffsetSeconds() >= -5 && value.upperOffsetSeconds() <= 5;
        if (!healthy) { leaseValid = false; remaining = 0; reason = "HEALTH_UNCONFIRMED"; }
        return healthy;
    }
    private boolean healthValid(long now) {
        if (!healthy) return false;
        long age = now - observedNano;
        if (age < 0 || age >= HEALTH_TTL_NANOS) return fail("HEALTH_STALE_OR_CLOCK_RESET");
        try {
            long wallElapsed = Math.subtractExact(wallMillis.getAsLong(), observedWall);
            long discrepancy = Math.subtractExact(wallElapsed, age / 1_000_000L);
            if (discrepancy < -5000 || discrepancy > 5000) return fail("WALL_CLOCK_DISCONTINUITY");
        } catch (ArithmeticException invalid) { return fail("WALL_CLOCK_DISCONTINUITY"); }
        return true;
    }
    private boolean fail(String why) { healthy = false; leaseValid = false; remaining = 0; reason = why; return false; }
    public synchronized Decision arm() {
        long now = monotonic.getAsLong();
        if (!healthValid(now)) return new Decision(false, reason, remaining);
        armedNano = now; leaseValid = true; remaining = 4; reason = "ARMED";
        return new Decision(true, reason, remaining);
    }
    public synchronized Decision status() { return decide(false); }
    public synchronized Decision checkAndConsume() { return decide(true); }
    private Decision decide(boolean consume) {
        long now = monotonic.getAsLong();
        if (!healthValid(now)) return new Decision(false, reason, 0);
        long elapsed = now - armedNano;
        if (!leaseValid || remaining <= 0) return new Decision(false, "LOCKED_OR_BUDGET_EXHAUSTED", 0);
        if (elapsed < 0 || elapsed >= LEASE_NANOS) {
            leaseValid = false; remaining = 0; reason = "LEASE_EXPIRED"; return new Decision(false, reason, 0);
        }
        if (consume) remaining--; return new Decision(true, "DIAGNOSTIC_ONLY", remaining);
    }
    public synchronized Decision validateCompletion() {
        if (!leaseValid) return new Decision(false, "LEASE_REVOKED", 0);
        long now = monotonic.getAsLong();
        if (!healthValid(now)) return new Decision(false, reason, 0);
        long elapsed = now - armedNano;
        if (elapsed < 0 || elapsed >= LEASE_NANOS) {
            leaseValid = false; remaining = 0; reason = "LEASE_EXPIRED"; return new Decision(false, reason, 0);
        }
        return new Decision(true, "DIAGNOSTIC_ONLY", remaining);
    }
    public synchronized void lock() { leaseValid = false; remaining = 0; reason = "EXPLICIT_LOCK"; }
}
