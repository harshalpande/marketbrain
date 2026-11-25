# Paytm Telegram review integration plan

Status: adapter locally verified on 25 November 2026; opt-in callback wiring implemented locally; publisher and spare runtime integration pending. G6 remains 0%, Paytm readiness 24/30 (80%).

The existing Telegram review configuration defaults to Upstox quotes and the Windows clock. Explicit quote-provider=PAYTM now selects the Paytm adapter and its VPS clock. It has no active proposal publisher. The new PaytmPaperReviewAdapter is deliberately an internal factory, now available as a managed bean only when review is explicitly enabled with quote-provider=PAYTM. The spare deployment has not activated it. It resolves instrument identity again for each review and reads a fresh quote from the authenticated supervised session using its VPS-anchored monotonic clock. It rejects missing/stale/mismatched data, expired or locked sessions and prices requiring fractional-paise rounding. Account, revision, quantity, notional and slippage decisions remain in the deterministic paper review engine.

Approved policy: PAPER_PAYTM_TEST_100S_V1, 100-second expiry, maximum quote age 15 seconds, maximum slippage 50 basis points, quantity 1, maximum notional 500000 paise (Rs5000). Earlier Upstox proposal policy identifiers cannot be reused. Successful acceptance records ACCEPTED_EXECUTION_BLOCKED.

## Sequential implementation and verification

1. Implemented locally: explicit opt-in Paytm callback wiring with the same authenticated VPS clock for proposal issuance and review. Preserve default-off behavior and the existing Upstox policy path. Test application startup, dependency wiring, locked-session denial and provider-policy mismatch.
2. Integrate a bounded review-only proposal publisher with the existing approval storage contract. Verify authenticated operator access, account revision binding, token hashing, idempotency and least-privilege database access. Do not use the restricted review writer as an unrestricted issuer.
3. Prepare one combined spare-laptop run: locally unlock the existing writer/session, issue clearly labelled ACCEPT, REJECT and expiry review proposals, deliver Telegram buttons, collect authenticated receipts, then test replay. The owner clicks ACCEPT/REJECT; expiry needs no click. Unauthorized-user and malformed-callback cases belong in isolated fixtures unless a separate test identity is explicitly provided.
4. Revalidate a real Paytm quote on ACCEPT; no stored quote can stand in for a new fetch. Plan issuance and acceptance within the existing three-quote session budget and five-second minimum spacing. If the budget cannot support the combined workflow, design and test an explicit bounded change before deployment; do not silently raise limits. REJECT, expiry and replay must not consume unnecessary quote calls.
5. Capture one automatically collected JSON containing case outcomes, timings, source revision, final receipts and cleanup. Assert no orders, reservations or fills; lock credentials/session and stop the test gateway after completion. Do not queue passwords, OTPs or raw callback tokens. Resume paper workflow integration only after reviewing this evidence.

## Local evidence and limits

133 tests passed: adapter18, supervised session22, bound-quote controller8, approval engine34, Paytm policy11, original policy6, Telegram configuration28 and Telegram verification6. No failures/errors/skips. These are local fixtures and regressions, not live Telegram or database deployment acceptance. No remote job or message was submitted for this code-only milestone. No spare-laptop rebuild is required yet.

## Callback configuration milestone

PAYTM requires PROCESS_MEMORY credentials and the exact PAPER_PAYTM_TEST_100S_V1 policy. It requires the supervised controller bean and fails startup without it; no Upstox or Windows-clock fallback occurs. Existing default-off and Upstox behavior remains covered by regressions. The runtime control socket is replaced by a mock only in the new offline Spring test; real credential handoff is not newly claimed.

Storage inspection confirms the restricted writer can record decisions through review functions but cannot issue proposals. Existing PaperApprovalDelivery can atomically issue tokens and enqueue encrypted delivery using separate authorized connections. Integrating that issuer and its bounded permissions is the next step; do not enable review on the spare machine before the combined deployment is ready.

Wiring validation: 103 targeted tests passed (12 new configuration cases), zero failures/errors/skips. See [wiring evidence](evidence/paytm-review-wiring-local-20261125.json).

## Publisher implementation and next verification

PaperPaytmReviewPublisher is an internal factory, not an enabled bean or HTTP endpoint. It prepares three BUY quantity-one review fixtures with case-labelled IDs, using a single Paytm reference quote, the active PRIMARY Telegram binding and the current ledger revision. The reference must be at most 15 seconds old and at most Rs5000; the upper price zone is capped at that notional. All have the approved 100-second window. The account must be consistent with enough unreserved cash for the zone. This is test review, not an AI-generated trading recommendation.

One reference fetch plus one fresh ACCEPT fetch uses two of the existing three session quote calls. The launcher must leave at least five seconds between provider calls. REJECT, expiry and replay require no extra provider fetch. Natural stale or out-of-zone conditions must be recorded as blocked, never treated as an accepted review.

The publisher verifies an existing bound encryption key and requires the separate marketbrain-paper-publisher role, rejecting a superuser, database/role creator, replication/bypass role or proposal-table owner/member. This account is NOT created by this change. Exact grants, credential custody, application wiring and combined runtime activation remain pending. The existing review writer cannot be used as publisher; no broad permission or owner-datasource fallback was introduced.

A prepared plan contains no button tokens. The future launcher must preserve that exact plan before dispatch; retry uses the original IDs/terms, never reprices or generates a new batch silently. enqueueBatch commits all three proposals/tokens/encrypted deliveries in one transaction, locks IDs in sorted order, and rejects duplicate or oversized batches. Each explicit dispatch uses the existing durable one-send claim. A SENDING or UNCERTAIN result needs reconciliation, not automatic resend.

Local verification: 115 Java tests, 92 offline PowerShell assertions (56 existing persistence plus 36 delivery assertions); zero failing assertions in final runs. These are fixtures, not PostgreSQL acceptance. Docker is unavailable on the development laptop. The updated disposable PostgreSQL suite adds actual three-item atomic enqueue, second-item rollback and token-preserving replay checks: 24 prepare checks plus three restart checks. It still uses fake HTTP and cannot call Paytm or Telegram.

Run on the spare laptop with Docker Desktop running:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\TestPaperPersistenceBundle.ps1 -ApprovalDelivery
```

This builds only the verification image and disposable database; it does not rebuild/restart MarketBrain. It produces one paper-delivery JSON. The existing automation allowlist does not yet expose this Docker suite; do not claim it was remotely submitted. Database batch acceptance and publisher-role deployment are separate from real G6 acceptance.

## 25 November: database batch accepted and next implementation contract

The isolated suite above is accepted: 24 prepare and 3 restart checks, 426.675 seconds, all 30 CRLF source hashes matched to b60d185. Do not rerun it unchanged. Read-only automation now collects the latest delivery report; this does not add remote Docker execution to the job allowlist.

The next deployment change must separate publisher operations from unrestricted table access. Inspection found that issuance locks portfolio/ledger rows and directly inserts proposal/token/outbox rows. Non-owner identity alone is not proof of restricted privileges. Do not grant portfolio/ledger UPDATE merely to satisfy FOR UPDATE; do not reuse the application owner or broaden the review writer.

Implement fixed-search-path, restricted publisher operations for atomic enqueue, durable dispatch claim and acknowledgement. Each operation must bind the active private recipient, exact policy, account revision and immutable proposal identity; no order/fill/reservation operations. Only the dedicated publisher receives execution permission. Claim must preserve no-resend behavior after uncertain outcomes. Test denied direct table mutations, wrong caller, conflicting/replayed batches, expired/revoked messages and crash recovery in the disposable database before any production role installation. Then integrate local credential/key custody and one combined Telegram test. No new secret input or spare-machine configuration change is needed for the design/fixture stage.

## Restricted publisher interface implementation

Candidate `paper/approval-publisher-v1.sql` now defines `paper_publish_enqueue`, `paper_publish_lock` and `paper_publish_transition`. This is not a Flyway migration. The isolated installer replaces validated schema and exact Java policy placeholders, revokes PUBLIC execution, transfers function ownership to a NOLOGIN non-owner helper, and grants only the publisher login execution plus required SELECT access. The helper alone has bounded insert/update/row-lock privileges. The production installer and credential provisioning remain unimplemented; fixture credentials must never be used there.

The publisher factory uses the restricted delivery path and rejects direct table or column mutation privileges. Preparation uses read-only account queries; the enqueue function locks and rechecks the active recipient, exact policy, instrument, account revision, cash and validity. The atomic three-proposal transaction remains in Java. Enqueue retries retain prior tokens. Dispatch commits its SENDING claim before sending; a crash or uncertain outcome cannot trigger automatic resend. Clock arguments come from the authenticated VPS-anchored Java clock; these functions do not substitute database wall time.

Verification completed locally: 51 Java tests (34 transport, 12 publisher, two batch transactions, three restricted-path/authority checks), plus 92 mocked PowerShell assertions. These do not establish SQL runtime acceptance. The disposable database suite is now 42 checks (36 prepare, six after restart), adding 15 restricted-role scenarios to the previously accepted 27. It creates roles/functions only in its disposable PostgreSQL container. MarketBrain and its database are untouched; all HTTP is fake.

Run the same `TestPaperPersistenceBundle.ps1 -ApprovalDelivery` command above after pulling the new revision. This rerun is needed because the interface and permissions changed. Its single report can now be fetched automatically through the existing queue. Successful isolated verification unlocks preparation of the production role/credential deployment, not live Telegram or order execution.

## Restricted database acceptance and application wiring

Run2fcd6e606e0247f0bc017ed6bc2867b9 passed all42 real disposable PostgreSQL checks in175.305 seconds. The collector job55ccab81-966c-442d-b48b-526c2351ac61 returned the report automatically. All37 source hashes match7b216bf. The prior SQL runtime gate is satisfied; do not rerun that unchanged suite.

PaperPublisherConfiguration is explicitly default-off. Opt-in requires PAPER, REVIEW_ONLY, PROCESS_MEMORY, an existing absolute approval-key path and the exact Paytm callback policy/dependencies. PaperPublisherRuntime starts locked and opens only the dedicated publisher connection after local unlock. Database name/OID, current/session role, role attributes and permissions are checked without falling back to the application datasource or review writer. Startup does not access the database, key file or broker, issue a proposal, or send Telegram messages.

Publisher credentials have a separate process-owned buffer and control socket at /run/marketbrain-publisher/control.sock. PaperRuntimeControl accepts an explicit --publisher target; default commands still address the writer socket. Credentials remain on stdin, never command arguments. Socket directory creation/mount permissions and Windows DPAPI credential provisioning are pending deployment work. A successful unlock indicates only memory custody, not database authentication. Runtime close erases the credential. No automatic scheduler, HTTP publication endpoint or order executor was added.

The next deployment milestone must provision the production publisher/helper roles and functions, verify exact grants, preserve the existing bound key, provision its separate credential and private socket directory, and add a bounded authenticated operator launcher. Only then enable combined ACCEPT/REJECT/expiry delivery. Keep marketbrain.paper.publisher.enabled absent/false until that deployment is complete. No application rebuild or new spare test is needed for this source-only milestone; pull the committed sources only.

Local validation: 95 Java tests passed with zero failures/errors, including existing writer/callback regressions, publisher role identity and secret erasure, locked startup, separate credentials and explicit socket selection, and rejection of invalid execution/provider/credential configurations. Spring socket binding is mocked in these local configuration tests; Linux socket deployment and production authentication are not established. [Wiring evidence](evidence/paytm-publisher-wiring-local-20261125.json).
