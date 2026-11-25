# Paytm Telegram review integration plan

Status: adapter locally verified on 25 November 2026; runtime integration pending. G6 remains 0%, Paytm readiness 24/30 (80%).

The existing Telegram review configuration uses Upstox quotes and the Windows clock. It has no active proposal publisher. The new PaytmPaperReviewAdapter is deliberately an internal factory, not an activated Spring bean. It resolves instrument identity again for each review and reads a fresh quote from the authenticated supervised session using its VPS-anchored monotonic clock. It rejects missing/stale/mismatched data, expired or locked sessions and prices requiring fractional-paise rounding. Account, revision, quantity, notional and slippage decisions remain in the deterministic paper review engine.

Approved policy: PAPER_PAYTM_TEST_100S_V1, 100-second expiry, maximum quote age 15 seconds, maximum slippage 50 basis points, quantity 1, maximum notional 500000 paise (Rs5000). Earlier Upstox proposal policy identifiers cannot be reused. Successful acceptance records ACCEPTED_EXECUTION_BLOCKED.

## Sequential implementation and verification

1. Add explicit opt-in Paytm callback wiring with the same authenticated VPS clock for proposal issuance and review. Preserve default-off behavior and the existing Upstox policy path. Test application startup, dependency wiring, locked-session denial and provider-policy mismatch.
2. Integrate a bounded review-only proposal publisher with the existing approval storage contract. Verify authenticated operator access, account revision binding, token hashing, idempotency and least-privilege database access. Do not use the restricted review writer as an unrestricted issuer.
3. Prepare one combined spare-laptop run: locally unlock the existing writer/session, issue clearly labelled ACCEPT, REJECT and expiry review proposals, deliver Telegram buttons, collect authenticated receipts, then test replay. The owner clicks ACCEPT/REJECT; expiry needs no click. Unauthorized-user and malformed-callback cases belong in isolated fixtures unless a separate test identity is explicitly provided.
4. Revalidate a real Paytm quote on ACCEPT; no stored quote can stand in for a new fetch. Plan issuance and acceptance within the existing three-quote session budget and five-second minimum spacing. If the budget cannot support the combined workflow, design and test an explicit bounded change before deployment; do not silently raise limits. REJECT, expiry and replay must not consume unnecessary quote calls.
5. Capture one automatically collected JSON containing case outcomes, timings, source revision, final receipts and cleanup. Assert no orders, reservations or fills; lock credentials/session and stop the test gateway after completion. Do not queue passwords, OTPs or raw callback tokens. Resume paper workflow integration only after reviewing this evidence.

## Local evidence and limits

133 tests passed: adapter18, supervised session22, bound-quote controller8, approval engine34, Paytm policy11, original policy6, Telegram configuration28 and Telegram verification6. No failures/errors/skips. These are local fixtures and regressions, not live Telegram or database deployment acceptance. No remote job or message was submitted for this code-only milestone. No spare-laptop rebuild is required yet.
