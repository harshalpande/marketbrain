package in.marketbrain.paper;

import java.math.BigInteger;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;

/** Offline accounting fixture only. Not a Spring bean, persistence adapter or trading endpoint. */
public final class PaperAccountEngineering {
    public static final String VERSION = "PAPER_ACCOUNT_ENGINEERING_V1";
    public static final long INITIAL_CASH_PAISE = 10_000_000L;
    public enum Side { BUY, SELL, HOLD }
    public enum Status { OPEN, PARTIAL, FILLED, CANCELLED, EXPIRED }

    /** Explicit engineering policy; these fixture limits are NOT approved deployment defaults. */
    public record Policy(long maxQuoteAgeMillis, int maxSlippageBps, long maxQuantity,
                         long maxOrderNotionalPaise, int maxApprovals, int maxFills) {
        public Policy {
            require(maxQuoteAgeMillis > 0 && maxQuoteAgeMillis <= 300_000, "Quote freshness policy required");
            require(maxSlippageBps >= 0 && maxSlippageBps <= 10_000, "Invalid slippage policy");
            require(maxQuantity > 0 && maxOrderNotionalPaise > 0, "Positive order limits required");
            require(maxApprovals > 0 && maxApprovals <= 10_000 && maxFills > 0 && maxFills <= 100_000,
                    "Bounded evidence limits required");
        }
    }
    public record Quote(String symbol, long pricePaise, Instant observedAt) {
        public Quote { token(symbol); require(pricePaise > 0, "Positive quote required"); Objects.requireNonNull(observedAt); }
    }
    public record Approval(String approvalId, String orderId, String symbol, Side side, long quantity,
                           long referencePaise, long zoneMinPaise, long zoneMaxPaise, long feeBudgetPaise,
                           Instant createdAt, Instant expiresAt) {
        public Approval {
            token(approvalId); token(orderId); token(symbol); Objects.requireNonNull(side);
            Objects.requireNonNull(createdAt); Objects.requireNonNull(expiresAt);
            require(expiresAt.isAfter(createdAt), "Positive validity window required");
            require(zoneMinPaise > 0 && zoneMaxPaise >= zoneMinPaise
                    && referencePaise >= zoneMinPaise && referencePaise <= zoneMaxPaise, "Invalid price zone");
            require(feeBudgetPaise >= 0, "Negative fee budget");
            require(side == Side.HOLD ? quantity == 0 && feeBudgetPaise == 0 : quantity > 0, "Invalid quantity");
        }
    }
    /** Caller evidence must be revalidated on approval AND every fill; not a substitute for a risk engine. */
    public record RiskPermit(String approvalId, String orderId, Instant assessedAt, boolean allowed) {
        public RiskPermit { token(approvalId); token(orderId); Objects.requireNonNull(assessedAt); }
    }
    public record Fill(String fillId, String orderId, long quantity, long pricePaise, long feePaise) {
        public Fill { token(fillId); token(orderId); require(quantity > 0 && pricePaise > 0 && feePaise >= 0, "Invalid fill"); }
    }
    public record Order(Approval approval, Instant approvedAt, Status status, long filledQuantity, long feesPaidPaise) {
        public long remaining() { return approval.quantity - filledQuantity; }
        public boolean active() { return status == Status.OPEN || status == Status.PARTIAL; }
    }
    public record Event(int sequence, String kind, String orderId, String fillId, String symbol,
                        Instant at, long quantity, long pricePaise, long feePaise, long debitPaise, long creditPaise) {}
    public record Audit(View account, List<Event> journal, long initialCashPaise, long debitPaise,
                        long creditPaise, long feesPaise, int syntheticOrdersCreated, int syntheticFillCount) {
        public Audit { journal = List.copyOf(journal); }
    }
    public record View(long cashPaise, long reservedCashPaise, long availableCashPaise,
                       Map<String, Long> holdings, Map<String, Long> reservedShares,
                       Map<String, Order> orders, int approvalCount, int fillCount) {
        public View { holdings = Map.copyOf(holdings); reservedShares = Map.copyOf(reservedShares); orders = Map.copyOf(orders); }
    }

    /** One in-memory account. All mutations serialized; failed commands leave balances/reservations untouched. */
    public static final class Account {
        private final Policy policy;
        private final Clock clock;
        private long cash = INITIAL_CASH_PAISE;
        private long totalDebits, totalCredits, totalFees;
        private final Map<String, Long> holdings = new TreeMap<>();
        private final Map<String, Approval> approvals = new LinkedHashMap<>();
        private final Map<String, String> orderOwners = new LinkedHashMap<>();
        private final Map<String, Order> orders = new LinkedHashMap<>();
        private final Map<String, Fill> fills = new LinkedHashMap<>();
        private final List<Event> journal = new ArrayList<>();
        private Instant lastMutation;

        public Account(Policy policy, Clock clock) { this.policy = Objects.requireNonNull(policy); this.clock = Objects.requireNonNull(clock); }

        /** Returns null for HOLD, which consumes its approval ID but never creates an order. */
        public synchronized Order approve(Approval command, Quote quote, RiskPermit permit) {
            Objects.requireNonNull(command);
            Approval old = approvals.get(command.approvalId);
            if (old != null) { require(old.equals(command), "Approval ID conflict"); return orders.get(command.orderId); }
            require(!orderOwners.containsKey(command.orderId), "Order ID already owned by another approval");
            require(approvals.size() < policy.maxApprovals, "Approval capacity reached");
            Instant now = now();
            require(!now.isBefore(command.createdAt) && now.isBefore(command.expiresAt), "Approval not currently valid");
            risk(command, permit, now);
            validateQuote(command, quote, now);
            require(!permit.assessedAt.isBefore(quote.observedAt), "Risk assessment predates executable quote");
            require(command.quantity <= policy.maxQuantity, "Quantity limit");
            long maximumNotional = Math.multiplyExact(command.quantity, command.zoneMaxPaise);
            require(maximumNotional <= policy.maxOrderNotionalPaise, "Order notional limit");
            View before = view();
            if (command.side == Side.BUY) {
                require(Math.addExact(maximumNotional, command.feeBudgetPaise) <= before.availableCashPaise, "Insufficient unreserved cash");
            } else if (command.side == Side.SELL) {
                long available = holdings.getOrDefault(command.symbol, 0L) - before.reservedShares.getOrDefault(command.symbol, 0L);
                require(command.quantity <= available, "Insufficient unreserved owned shares");
            }
            Order order = command.side == Side.HOLD ? null : new Order(command, now, Status.OPEN, 0, 0);
            approvals.put(command.approvalId, command); orderOwners.put(command.orderId, command.approvalId);
            if (order != null) orders.put(command.orderId, order);
            journal.add(new Event(journal.size() + 1, command.side == Side.HOLD ? "HOLD_NO_ORDER" : "APPROVED",
                    command.orderId, null, command.symbol, now, command.quantity, 0, 0, 0, 0));
            lastMutation = now;
            return order;
        }

        public synchronized Order fill(Fill fill, Quote quote, RiskPermit permit) {
            Objects.requireNonNull(fill);
            Fill old = fills.get(fill.fillId);
            if (old != null) { require(old.equals(fill), "Fill ID conflict"); return orders.get(fill.orderId); }
            require(fills.size() < policy.maxFills, "Fill capacity reached");
            Order order = requiredOrder(fill.orderId);
            require(order.active(), "Order is terminal");
            Instant now = now();
            Approval a = order.approval;
            require(now.isBefore(a.expiresAt), "Order expired: release using expireDue");
            risk(a, permit, now); validateQuote(a, quote, now); price(a, fill.pricePaise);
            require(!permit.assessedAt.isBefore(quote.observedAt), "Risk assessment predates executable quote");
            require(!quote.observedAt.isBefore(order.approvedAt) && !permit.assessedAt.isBefore(order.approvedAt), "Fill evidence predates approval");
            require(fill.quantity <= order.remaining(), "Overfill");
            require(a.side == Side.BUY ? fill.pricePaise >= quote.pricePaise : fill.pricePaise <= quote.pricePaise,
                    "Optimistic fill versus supplied executable quote");
            long newFees = Math.addExact(order.feesPaidPaise, fill.feePaise);
            require(newFees <= a.feeBudgetPaise, "Fee budget exceeded");
            long notional = Math.multiplyExact(fill.quantity, fill.pricePaise);
            long owned = holdings.getOrDefault(a.symbol, 0L);
            long newCash, newOwned;
            if (a.side == Side.BUY) {
                newCash = Math.subtractExact(cash, Math.addExact(notional, fill.feePaise));
                newOwned = Math.addExact(owned, fill.quantity);
            } else {
                require(fill.feePaise <= notional, "Fee exceeds sale proceeds");
                newCash = Math.addExact(cash, Math.subtractExact(notional, fill.feePaise));
                newOwned = Math.subtractExact(owned, fill.quantity);
            }
            require(newCash >= 0 && newOwned >= 0, "Negative account balance");
            long debit = a.side == Side.BUY ? Math.addExact(notional, fill.feePaise) : 0;
            long credit = a.side == Side.SELL ? Math.subtractExact(notional, fill.feePaise) : 0;
            long nextDebits = Math.addExact(totalDebits, debit), nextCredits = Math.addExact(totalCredits, credit);
            long nextFees = Math.addExact(totalFees, fill.feePaise);
            long newFilled = Math.addExact(order.filledQuantity, fill.quantity);
            Order updated = new Order(a, order.approvedAt, newFilled == a.quantity ? Status.FILLED : Status.PARTIAL, newFilled, newFees);
            // All fallible arithmetic and checks precede mutation.
            cash = newCash; holdings.put(a.symbol, newOwned); orders.put(a.orderId, updated); fills.put(fill.fillId, fill);
            totalDebits = nextDebits; totalCredits = nextCredits; totalFees = nextFees;
            journal.add(new Event(journal.size() + 1, a.side == Side.BUY ? "BUY_FILL" : "SELL_FILL", a.orderId, fill.fillId,
                    a.symbol, now, fill.quantity, fill.pricePaise, fill.feePaise,
                    debit, credit));
            lastMutation = now;
            return updated;
        }

        public synchronized Order cancel(String orderId) {
            Order order = requiredOrder(orderId);
            if (!order.active()) return order;
            Instant now = now();
            Order updated = new Order(order.approval, order.approvedAt, Status.CANCELLED, order.filledQuantity, order.feesPaidPaise);
            orders.put(orderId, updated);
            journal.add(new Event(journal.size() + 1, "CANCELLED", orderId, null, order.approval.symbol, now,
                    order.remaining(), 0, 0, 0, 0));
            lastMutation = now; return updated;
        }

        public synchronized int expireDue() {
            Instant now = now(); int count = 0;
            for (var pair : orders.entrySet()) {
                Order o = pair.getValue();
                if (o.active() && !now.isBefore(o.approval.expiresAt)) {
                    pair.setValue(new Order(o.approval, o.approvedAt, Status.EXPIRED, o.filledQuantity, o.feesPaidPaise)); count++;
                    journal.add(new Event(journal.size() + 1, "EXPIRED", o.approval.orderId, null, o.approval.symbol,
                            now, o.remaining(), 0, 0, 0, 0));
                }
            }
            if (count > 0) lastMutation = now;
            return count;
        }

        public synchronized View view() {
            long reserved = 0; Map<String, Long> shares = new TreeMap<>();
            for (Order o : orders.values()) if (o.active()) {
                if (o.approval.side == Side.BUY) reserved = Math.addExact(reserved,
                        Math.addExact(Math.multiplyExact(o.remaining(), o.approval.zoneMaxPaise), o.approval.feeBudgetPaise - o.feesPaidPaise));
                else shares.merge(o.approval.symbol, o.remaining(), Math::addExact);
            }
            return new View(cash, reserved, Math.subtractExact(cash, reserved), holdings, shares, orders, approvals.size(), fills.size());
        }
        public synchronized Audit audit() {
            long debits = 0, credits = 0, fees = 0;
            for (Event e : journal) { debits = Math.addExact(debits, e.debitPaise); credits = Math.addExact(credits, e.creditPaise); fees = Math.addExact(fees, e.feePaise); }
            return new Audit(view(), journal, INITIAL_CASH_PAISE, debits, credits, fees, orders.size(), fills.size());
        }
        private Order requiredOrder(String id) { Order o = orders.get(id); require(o != null, "Unknown order"); return o; }
        private Instant now() {
            Instant now = clock.instant(); require(lastMutation == null || !now.isBefore(lastMutation), "Clock moved backwards"); return now;
        }
        private void risk(Approval a, RiskPermit p, Instant now) {
            require(p != null && p.allowed && p.orderId.equals(a.orderId) && p.approvalId.equals(a.approvalId), "Missing or mismatched risk permit");
            fresh(p.assessedAt, now, "Risk assessment");
            require(!p.assessedAt.isBefore(a.createdAt), "Risk assessment predates proposal");
        }
        private void validateQuote(Approval a, Quote q, Instant now) {
            require(q != null && q.symbol.equals(a.symbol), "Quote symbol mismatch"); fresh(q.observedAt, now, "Quote");
            require(!q.observedAt.isBefore(a.createdAt), "Quote predates proposal"); price(a, q.pricePaise);
        }
        private void fresh(Instant observed, Instant now, String label) {
            require(!observed.isAfter(now) && Duration.between(observed, now).compareTo(Duration.ofMillis(policy.maxQuoteAgeMillis)) <= 0,
                    label + " stale or future dated");
        }
        private void price(Approval a, long value) {
            require(value >= a.zoneMinPaise && value <= a.zoneMaxPaise, "Price outside approved zone");
            BigInteger distance = BigInteger.valueOf(value).subtract(BigInteger.valueOf(a.referencePaise)).abs().multiply(BigInteger.valueOf(10_000));
            require(distance.compareTo(BigInteger.valueOf(a.referencePaise).multiply(BigInteger.valueOf(policy.maxSlippageBps))) <= 0, "Slippage limit");
        }
    }

    private static void token(String value) { require(value != null && value.matches("[A-Za-z0-9_.:-]{1,100}"), "Invalid identifier"); }
    private static void require(boolean condition, String message) { if (!condition) throw new IllegalArgumentException(message); }
    public static final class FixtureClock extends Clock {
        private Instant instant;
        public FixtureClock(Instant instant) { this.instant = Objects.requireNonNull(instant); }
        public void set(Instant value) { instant = Objects.requireNonNull(value); }
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { require(ZoneOffset.UTC.equals(zone), "UTC fixture only"); return this; }
        @Override public Instant instant() { return instant; }
    }
    static final Instant T = Instant.parse("2026-01-05T04:30:00Z");
    static Policy fixturePolicy() { return new Policy(5_000, 200, 10_000, INITIAL_CASH_PAISE, 50, 100); }
    static Approval proposal(String id, Side side, long quantity) {
        return new Approval("APP-" + id, id, "FIXTURE", side, quantity, 10_000, 9_900, 10_100,
                side == Side.HOLD ? 0 : 100, T, T.plusSeconds(120));
    }
    static Quote quote(long price) { return new Quote("FIXTURE", price, T); }
    static RiskPermit permit(Approval a) { return new RiskPermit(a.approvalId, a.orderId, T, true); }
    static Account account() { return new Account(fixturePolicy(), Clock.fixed(T, ZoneOffset.UTC)); }
    static Account bought() {
        Account a = account(); Approval p = proposal("buy", Side.BUY, 10); a.approve(p, quote(10_000), permit(p));
        a.fill(new Fill("buy-fill", "buy", 10, 10_000, 20), quote(10_000), permit(p)); return a;
    }
    static Audit auditExample() {
        Account a = account(); Approval b = proposal("buy", Side.BUY, 10); a.approve(b, quote(10_000), permit(b));
        a.fill(new Fill("buy1", "buy", 4, 10_000, 10), quote(10_000), permit(b));
        a.fill(new Fill("buy2", "buy", 6, 10_000, 10), quote(10_000), permit(b));
        Approval s = proposal("sell", Side.SELL, 4); a.approve(s, quote(10_000), permit(s));
        a.fill(new Fill("sell1", "sell", 2, 10_000, 10), quote(10_000), permit(s)); a.cancel("sell");
        Approval next = proposal("pending", Side.BUY, 2); a.approve(next, quote(10_000), permit(next)); return a.audit();
    }
    static void rejects(Runnable operation) { boolean failed = false; try { operation.run(); } catch (IllegalArgumentException | ArithmeticException expected) { failed = true; } require(failed, "Expected rejection"); }
    static void eq(Object actual, Object expected) { require(Objects.equals(actual, expected), "Expected " + expected + "; got " + actual); }
    public record Check(String name, boolean passed, double elapsedMillis, String failure) {}
    static void check(List<Check> checks, String name, Runnable run) {
        long start = System.nanoTime(); String failure = null;
        try { run.run(); } catch (Exception | AssertionError e) { failure = e.getClass().getSimpleName() + ": " + e.getMessage(); }
        checks.add(new Check(name, failure == null, (System.nanoTime() - start) / 1_000_000.0, failure));
    }
    public static Map<String, Object> runSuite() {
        long started = System.nanoTime(); List<Check> c = new ArrayList<>();
        check(c, "initial_capital_exact", () -> eq(account().view().cashPaise, 10_000_000L));
        check(c, "hold_creates_no_order", () -> { Account a = account(); Approval p = proposal("h", Side.HOLD, 0); eq(a.approve(p, quote(10_000), permit(p)), null); eq(a.view().orders.size(), 0); });
        check(c, "buy_reserves_cash_and_costs", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); eq(a.view().reservedCashPaise, 101_100L); });
        check(c, "duplicate_approval_no_double_reservation", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); View v = a.view(); a.approve(p, null, null); eq(a.view(), v); });
        check(c, "approval_id_conflict_rejected", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); View v = a.view(); rejects(() -> a.approve(proposal("b", Side.BUY, 20), quote(10_000), permit(p))); eq(a.view(), v); });
        check(c, "cash_cannot_be_double_reserved", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 900); a.approve(p, quote(10_000), permit(p)); Approval p2 = proposal("b2", Side.BUY, 100); rejects(() -> a.approve(p2, quote(10_000), permit(p2))); });
        check(c, "partial_buy_reconciles_reservation", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); a.fill(new Fill("f", "b", 4, 10_000, 20), quote(10_000), permit(p)); eq(a.view().cashPaise, 9_959_980L); eq(a.view().reservedCashPaise, 60_680L); eq(a.view().holdings.get("FIXTURE"), 4L); });
        check(c, "duplicate_fill_no_double_debit", () -> { Account a = bought(); View v = a.view(); a.fill(new Fill("buy-fill", "buy", 10, 10_000, 20), null, null); eq(a.view(), v); });
        check(c, "fill_id_conflict_rejected", () -> { Account a = bought(); rejects(() -> a.fill(new Fill("buy-fill", "buy", 9, 10_000, 20), null, null)); });
        check(c, "sell_requires_owned_shares", () -> { Account a = account(); Approval p = proposal("s", Side.SELL, 1); rejects(() -> a.approve(p, quote(10_000), permit(p))); });
        check(c, "sell_cannot_double_reserve_shares", () -> { Account a = bought(); Approval p = proposal("s", Side.SELL, 6); a.approve(p, quote(10_000), permit(p)); Approval p2 = proposal("s2", Side.SELL, 5); rejects(() -> a.approve(p2, quote(10_000), permit(p2))); });
        check(c, "partial_sell_reconciles_net_proceeds", () -> { Account a = bought(); Approval p = proposal("s", Side.SELL, 6); a.approve(p, quote(10_000), permit(p)); a.fill(new Fill("sf", "s", 2, 10_000, 10), quote(10_000), permit(p)); eq(a.view().cashPaise, 9_919_970L); eq(a.view().holdings.get("FIXTURE"), 8L); eq(a.view().reservedShares.get("FIXTURE"), 4L); });
        check(c, "cancel_releases_only_unfilled_reservation", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); a.fill(new Fill("f", "b", 4, 10_000, 20), quote(10_000), permit(p)); a.cancel("b"); eq(a.view().reservedCashPaise, 0L); eq(a.view().cashPaise, 9_959_980L); eq(a.view().holdings.get("FIXTURE"), 4L); });
        check(c, "expiry_releases_reservation", () -> { FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); clock.set(p.expiresAt); eq(a.expireDue(), 1); eq(a.expireDue(), 0); eq(a.view().reservedCashPaise, 0L); });
        check(c, "expired_order_cannot_fill", () -> { FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock); Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p)); clock.set(p.expiresAt); rejects(() -> a.fill(new Fill("f", "b", 1, 10_000, 0), quote(10_000), permit(p))); });
        check(c, "stale_and_future_quotes_rejected", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); rejects(() -> a.approve(p, new Quote("FIXTURE", 10_000, T.minusSeconds(6)), permit(p))); rejects(() -> a.approve(p, new Quote("FIXTURE", 10_000, T.plusSeconds(1)), permit(p))); });
        check(c, "out_of_zone_buy_not_chased", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); rejects(() -> a.approve(p, quote(10_101), permit(p))); });
        check(c, "slippage_guard_independent_of_zone", () -> { Account a = new Account(new Policy(5_000, 1, 100, INITIAL_CASH_PAISE, 10, 10), Clock.fixed(T, ZoneOffset.UTC)); Approval p = proposal("b", Side.BUY, 1); rejects(() -> a.approve(p, quote(10_002), permit(p))); });
        check(c, "risk_revalidated_at_fill", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p)); rejects(() -> a.fill(new Fill("f", "b", 1, 10_000, 0), quote(10_000), new RiskPermit(p.approvalId, p.orderId, T, false))); });
        check(c, "optimistic_fill_rejected", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p)); rejects(() -> a.fill(new Fill("f", "b", 1, 9_999, 0), quote(10_000), permit(p))); });
        check(c, "fee_overrun_rejected_atomically", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p)); View v = a.view(); rejects(() -> a.fill(new Fill("f", "b", 1, 10_000, 101), quote(10_000), permit(p))); eq(a.view(), v); });
        check(c, "overfill_rejected", () -> { Account a = account(); Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p)); rejects(() -> a.fill(new Fill("f", "b", 2, 10_000, 0), quote(10_000), permit(p))); });
        check(c, "overflow_rejected_before_mutation", () -> { Account a = new Account(new Policy(5_000, 200, Long.MAX_VALUE, Long.MAX_VALUE, 10, 10), Clock.fixed(T, ZoneOffset.UTC)); Approval p = proposal("b", Side.BUY, Long.MAX_VALUE); View v = a.view(); rejects(() -> a.approve(p, quote(10_000), permit(p))); eq(a.view(), v); });
        check(c, "clock_rollback_blocks_mutation", () -> { FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock); Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p)); clock.set(T.minusSeconds(1)); rejects(() -> a.cancel("b")); });
        check(c, "terminal_order_not_reopened", () -> { Account a = bought(); a.cancel("buy"); eq(a.view().orders.get("buy").status, Status.FILLED); rejects(() -> a.fill(new Fill("new", "buy", 1, 10_000, 0), quote(10_000), permit(proposal("buy", Side.BUY, 10)))); });
        check(c, "bounded_account_no_implicit_eviction", () -> { Account a = new Account(new Policy(5_000, 200, 100, INITIAL_CASH_PAISE, 1, 1), Clock.fixed(T, ZoneOffset.UTC)); Approval p = proposal("h", Side.HOLD, 0); a.approve(p, quote(10_000), permit(p)); Approval p2 = proposal("h2", Side.HOLD, 0); rejects(() -> a.approve(p2, quote(10_000), permit(p2))); });
        long failed = c.stream().filter(x -> !x.passed).count(); Map<String, Object> out = new TreeMap<>();
        out.put("version", VERSION); out.put("status", failed == 0 ? "ENGINEERING_CHECKS_PASSED" : "ENGINEERING_CHECKS_FAILED");
        out.put("checks", c); out.put("checkCount", c.size()); out.put("failedCount", failed); out.put("initialCashPaise", INITIAL_CASH_PAISE);
        out.put("syntheticOnly", true); out.put("runtimePaperAccountEnabled", false); out.put("databaseWritesPerformed", false);
        for (String field : List.of("providerCallCount", "modelCallCount", "ordersCreated", "signalsCreated")) out.put(field, 0);
        out.put("actionExecutionEnabled", false); out.put("fixturePolicyNotRuntimeDefaults", fixturePolicy());
        out.put("accountingEvidence", auditExample());
        out.put("externalActionCounterScope", "ordersCreated excludes ephemeral fixture orders; accountingEvidence reports syntheticOrdersCreated and syntheticFillCount");
        out.put("runtimeVersion", System.getProperty("java.version"));
        out.put("elapsedMillis", (System.nanoTime() - started) / 1_000_000.0); return out;
    }
    public static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Number || value instanceof Boolean) return value.toString();
        if (value instanceof Map<?, ?> m) { List<String> items = new ArrayList<>(); m.forEach((k,v) -> items.add(json(k.toString()) + ":" + json(v))); return "{" + String.join(",", items) + "}"; }
        if (value instanceof Iterable<?> a) { List<String> items = new ArrayList<>(); a.forEach(v -> items.add(json(v))); return "[" + String.join(",", items) + "]"; }
        if (value.getClass().isRecord()) { Map<String,Object> m = new TreeMap<>(); try { for (var field : value.getClass().getRecordComponents()) m.put(field.getName(), field.getAccessor().invoke(value)); } catch (ReflectiveOperationException e) { throw new IllegalStateException(e); } return json(m); }
        String s = value.toString(); StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) { if (c == '\\' || c == '"') b.append('\\').append(c); else if (c < 32) b.append(String.format("\\u%04x", (int)c)); else b.append(c); }
        return b.append('"').toString();
    }
    public static void main(String[] args) {
        require(args.length == 1 && "--synthetic-paper".equals(args[0]), "Only --synthetic-paper is supported; no runtime account activation");
        Map<String,Object> result = runSuite(); System.out.println(json(result));
        if (!"ENGINEERING_CHECKS_PASSED".equals(result.get("status"))) System.exit(2);
    }
}
