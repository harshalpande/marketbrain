package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import java.time.Clock;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static org.junit.jupiter.api.Assertions.*;

class PaperAccountEngineeringTest {
    @Test void allFixedChecksPassWithoutRuntimeActivation() {
        var result = runSuite();
        assertEquals("ENGINEERING_CHECKS_PASSED", result.get("status"));
        assertEquals(26, result.get("checkCount")); assertEquals(0L, result.get("failedCount"));
        assertEquals(false, result.get("runtimePaperAccountEnabled"));
        assertEquals(false, result.get("databaseWritesPerformed"));
    }
    @Test void journalIndependentlyReconcilesMoneyAndQuantity() {
        Audit audit = auditExample(); long debit = 0, credit = 0, shares = 0, fees = 0; int seq = 0;
        for (Event e : audit.journal()) {
            assertEquals(++seq, e.sequence());
            if (e.kind().equals("BUY_FILL")) { assertEquals(e.quantity() * e.pricePaise() + e.feePaise(), e.debitPaise()); shares += e.quantity(); }
            if (e.kind().equals("SELL_FILL")) { assertEquals(e.quantity() * e.pricePaise() - e.feePaise(), e.creditPaise()); shares -= e.quantity(); }
            debit += e.debitPaise(); credit += e.creditPaise(); fees += e.feePaise();
        }
        assertEquals(7, seq); assertEquals(30, fees); assertEquals(debit, audit.debitPaise()); assertEquals(credit, audit.creditPaise());
        assertEquals(INITIAL_CASH_PAISE + credit - debit, audit.account().cashPaise());
        assertEquals(audit.account().cashPaise() - audit.account().reservedCashPaise(), audit.account().availableCashPaise());
        assertEquals(shares, audit.account().holdings().get("FIXTURE"));
        assertEquals(3, audit.syntheticOrdersCreated()); assertEquals(3, audit.syntheticFillCount());
    }
    @Test void snapshotAndJournalAreImmutable() {
        Audit a = auditExample();
        assertThrows(UnsupportedOperationException.class, () -> a.account().holdings().put("BAD", 1L));
        assertThrows(UnsupportedOperationException.class, () -> a.account().orders().clear());
        assertThrows(UnsupportedOperationException.class, () -> a.journal().clear());
    }
    @Test void orderIdCannotBeUsedByDifferentApproval() {
        Account a = account(); Approval p = proposal("b", Side.BUY, 2); a.approve(p, quote(10_000), permit(p));
        Approval another = new Approval("DIFFERENT", p.orderId(), p.symbol(), p.side(), p.quantity(), p.referencePaise(),
                p.zoneMinPaise(), p.zoneMaxPaise(), p.feeBudgetPaise(), p.createdAt(), p.expiresAt());
        assertThrows(IllegalArgumentException.class, () -> a.approve(another, quote(10_000), permit(another)));
    }
    @Test void cancelledSellReleasesSharesNotCashOrOwnedQuantity() {
        Account a = bought(); Approval p = proposal("s", Side.SELL, 8); a.approve(p, quote(10_000), permit(p));
        long cash = a.view().cashPaise(); a.cancel("s"); a.cancel("s");
        assertEquals(cash, a.view().cashPaise()); assertEquals(10L, a.view().holdings().get("FIXTURE"));
        assertTrue(a.view().reservedShares().isEmpty());
        assertEquals(1L, a.audit().journal().stream().filter(e -> e.kind().equals("CANCELLED")).count());
    }
    @Test void expiryAfterPartialBuyPreservesFillAndReleasesOnlyRemainder() {
        FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock);
        Approval p = proposal("b", Side.BUY, 10); a.approve(p, quote(10_000), permit(p));
        a.fill(new Fill("f", "b", 3, 10_000, 4), quote(10_000), permit(p)); clock.set(p.expiresAt());
        assertEquals(1, a.expireDue()); assertEquals(0, a.expireDue());
        assertEquals(0L, a.view().reservedCashPaise()); assertEquals(9_969_996L, a.view().cashPaise());
        assertEquals(3L, a.view().holdings().get("FIXTURE")); assertEquals(Status.EXPIRED, a.view().orders().get("b").status());
        assertEquals(7, a.audit().journal().getLast().quantity());
    }
    @Test void expiryAfterPartialSellPreservesFillAndReleasesRemainingShares() {
        FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock);
        Approval b = proposal("b", Side.BUY, 10); a.approve(b, quote(10_000), permit(b)); a.fill(new Fill("bf", "b", 10, 10_000, 0), quote(10_000), permit(b));
        Approval s = proposal("s", Side.SELL, 10); a.approve(s, quote(10_000), permit(s)); a.fill(new Fill("sf", "s", 2, 10_000, 0), quote(10_000), permit(s));
        clock.set(s.expiresAt()); assertEquals(1, a.expireDue()); assertTrue(a.view().reservedShares().isEmpty()); assertEquals(8L, a.view().holdings().get("FIXTURE"));
    }
    @Test void fullBuyReleasesUnusedFeeAllowance() {
        Account a = bought(); assertEquals(0L, a.view().reservedCashPaise()); assertEquals(9_899_980L, a.view().availableCashPaise());
    }
    @Test void feesAreCumulativeAndCannotConsumeOtherOrdersReservation() {
        Account a = account(); Approval p = proposal("b", Side.BUY, 2); a.approve(p, quote(10_000), permit(p));
        a.fill(new Fill("f1", "b", 1, 10_000, 80), quote(10_000), permit(p)); View v = a.view();
        assertThrows(IllegalArgumentException.class, () -> a.fill(new Fill("f2", "b", 1, 10_000, 21), quote(10_000), permit(p)));
        assertEquals(v, a.view()); a.fill(new Fill("f2", "b", 1, 10_000, 20), quote(10_000), permit(p)); assertEquals(Status.FILLED, a.view().orders().get("b").status());
    }
    @Test void negativeFeesAndZeroQuantityRejected() {
        assertThrows(IllegalArgumentException.class, () -> new Fill("f", "b", 1, 100, -1));
        assertThrows(IllegalArgumentException.class, () -> new Fill("f", "b", 0, 100, 0));
        assertThrows(IllegalArgumentException.class, () -> proposal("h", Side.HOLD, 1));
    }
    @Test void wrongQuoteSymbolAndRiskIdentityRejected() {
        Account a = account(); Approval p = proposal("b", Side.BUY, 1);
        assertThrows(IllegalArgumentException.class, () -> a.approve(p, new Quote("OTHER", 10_000, T), permit(p)));
        assertThrows(IllegalArgumentException.class, () -> a.approve(p, quote(10_000), new RiskPermit("APP-other", "other", T, true)));
    }
    @Test void riskMustBeAssessedAfterSuppliedQuoteForApprovalAndFill() {
        FixtureClock clock = new FixtureClock(T.plusSeconds(4)); Account a = new Account(fixturePolicy(), clock);
        Approval p = proposal("b", Side.BUY, 2); Quote current = new Quote("FIXTURE", 10_000, T.plusSeconds(4));
        assertThrows(IllegalArgumentException.class, () -> a.approve(p, current, permit(p)));
        RiskPermit approved = new RiskPermit(p.approvalId(), p.orderId(), T.plusSeconds(4), true); a.approve(p, current, approved);
        clock.set(T.plusSeconds(5)); Quote newer = new Quote("FIXTURE", 10_000, clock.instant());
        assertThrows(IllegalArgumentException.class, () -> a.fill(new Fill("f", "b", 1, 10_000, 0), newer, approved));
    }
    @Test void fillEvidenceCannotPredateActualApproval() {
        FixtureClock clock = new FixtureClock(T.plusSeconds(2)); Account a = new Account(fixturePolicy(), clock);
        Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), new RiskPermit(p.approvalId(), p.orderId(), clock.instant(), true));
        assertThrows(IllegalArgumentException.class, () -> a.fill(new Fill("f", "b", 1, 10_000, 0), quote(10_000), permit(p)));
    }
    @Test void expiredApprovalAndFutureProposalAreRejected() {
        Approval p = proposal("b", Side.BUY, 1);
        Account late = new Account(fixturePolicy(), Clock.fixed(p.expiresAt(), ZoneOffset.UTC));
        Account early = new Account(fixturePolicy(), Clock.fixed(T.minusSeconds(1), ZoneOffset.UTC));
        assertThrows(IllegalArgumentException.class, () -> late.approve(p, quote(10_000), permit(p)));
        assertThrows(IllegalArgumentException.class, () -> early.approve(p, quote(10_000), permit(p)));
    }
    @Test void exactFreshnessBoundaryAcceptedButOneNanosecondLaterRejected() {
        FixtureClock clock = new FixtureClock(T.plusSeconds(5)); Account a = new Account(fixturePolicy(), clock);
        Approval p = proposal("b", Side.BUY, 1); a.approve(p, quote(10_000), permit(p));
        Account later = new Account(fixturePolicy(), Clock.fixed(T.plusSeconds(5).plusNanos(1), ZoneOffset.UTC));
        assertThrows(IllegalArgumentException.class, () -> later.approve(p, quote(10_000), permit(p)));
    }
    @Test void duplicateFillAfterExpiryDoesNotRevalidateOrDebitAgain() {
        FixtureClock clock = new FixtureClock(T); Account a = new Account(fixturePolicy(), clock); Approval p = proposal("b", Side.BUY, 1);
        a.approve(p, quote(10_000), permit(p)); Fill f = new Fill("f", "b", 1, 10_000, 0); a.fill(f, quote(10_000), permit(p));
        Audit before = a.audit(); clock.set(T.plusSeconds(500)); a.fill(f, null, null); assertEquals(before, a.audit());
    }
    @Test void lowerSellPriceAllowedButBetterThanSuppliedExecutableQuoteRejected() {
        Account a = bought(); Approval s = proposal("s", Side.SELL, 1); a.approve(s, quote(10_000), permit(s));
        assertThrows(IllegalArgumentException.class, () -> a.fill(new Fill("s1", "s", 1, 10_001, 0), quote(10_000), permit(s)));
        a.fill(new Fill("s1", "s", 1, 9_999, 0), quote(10_000), permit(s)); assertEquals(9L, a.view().holdings().get("FIXTURE"));
    }
    @Test void fillCapacityDoesNotLoseExistingEvidence() {
        Account a = new Account(new Policy(5_000, 200, 100, INITIAL_CASH_PAISE, 10, 1), Clock.fixed(T, ZoneOffset.UTC));
        Approval p = proposal("b", Side.BUY, 2); a.approve(p, quote(10_000), permit(p)); a.fill(new Fill("f1", "b", 1, 10_000, 0), quote(10_000), permit(p));
        Audit old = a.audit(); assertThrows(IllegalArgumentException.class, () -> a.fill(new Fill("f2", "b", 1, 10_000, 0), quote(10_000), permit(p))); assertEquals(old, a.audit());
    }
    @Test void concurrentApprovalsCannotDoubleSpend() throws Exception {
        Account a = account(); CountDownLatch go = new CountDownLatch(1); AtomicInteger accepted = new AtomicInteger(); List<Thread> threads = new ArrayList<>();
        for (int i = 0; i < 8; i++) { final int id = i; Thread thread = new Thread(() -> {
            try { go.await(); Approval p = proposal("b" + id, Side.BUY, 900); a.approve(p, quote(10_000), permit(p)); accepted.incrementAndGet(); }
            catch (IllegalArgumentException expected) {} catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
        }); threads.add(thread); thread.start(); }
        go.countDown(); for (Thread t : threads) { t.join(5_000); assertFalse(t.isAlive()); }
        assertEquals(1, accepted.get()); assertTrue(a.view().availableCashPaise() >= 0); assertEquals(1, a.view().approvalCount());
    }
    @Test void noRuntimeCliAndNoImplicitPolicyDefaults() {
        assertThrows(IllegalArgumentException.class, () -> main(new String[]{"--live"}));
        assertThrows(IllegalArgumentException.class, () -> new Policy(0, 100, 100, 100, 10, 10));
        assertThrows(IllegalArgumentException.class, () -> new Policy(5_000, 100, 100, 100, 0, 10));
    }
}
