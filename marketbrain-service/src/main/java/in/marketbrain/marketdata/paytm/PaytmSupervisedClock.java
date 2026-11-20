package in.marketbrain.marketdata.paytm;

import java.time.*;
import java.util.function.LongSupplier;

/** VPS UTC anchor advanced by elapsed process time, independent of the laptop wall clock. */
public final class PaytmSupervisedClock extends Clock {
    private final Instant anchor;
    private final long started;
    private final LongSupplier ticks;
    private final Duration lifetime;

    public PaytmSupervisedClock(Instant vpsUtc, Duration lifetime) {
        this(vpsUtc, lifetime, System::nanoTime);
    }
    PaytmSupervisedClock(Instant vpsUtc, Duration lifetime, LongSupplier ticks) {
        this.anchor = java.util.Objects.requireNonNull(vpsUtc);
        if (lifetime == null || lifetime.isZero() || lifetime.isNegative()
                || lifetime.compareTo(Duration.ofMinutes(20)) > 0) throw new IllegalArgumentException("SESSION_LIFETIME_INVALID");
        this.lifetime = lifetime;
        this.ticks = ticks;
        this.started = ticks.getAsLong();
    }
    @Override public Instant instant() {
        long elapsed = ticks.getAsLong() - started;
        if (elapsed < 0 || elapsed >= lifetime.toNanos()) throw new IllegalStateException("SUPERVISED_SESSION_EXPIRED");
        return anchor.plusNanos(elapsed);
    }
    @Override public ZoneId getZone() { return ZoneOffset.UTC; }
    @Override public Clock withZone(ZoneId zone) {
        if (!ZoneOffset.UTC.equals(zone)) throw new IllegalArgumentException("UTC_REQUIRED");
        return this;
    }
}
