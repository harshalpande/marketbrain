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

## Off-hours installation rehearsal

PaperPublisherInstallation is the shared administrative transaction engine. It is not a startup migration or an operator command and is not invoked against the application database in this release. It requires a dedicated administrative connection and exact database name/OID/schema. It rejects existing publisher/helper roles and existing publication function names, refuses schemas with PUBLIC CREATE, bounds statement and lock waits, and locks dependencies before changing anything. It grants only the reviewed table/column permissions and the three restricted function entrypoints. Existing role/function definitions are not silently adopted, replaced or dropped. No blanket revocation of unrelated application permissions occurs.

REHEARSE_ROLLBACK executes the installation and rolls it back. INSTALL_DISABLED commits both roles as NOLOGIN without passwords; it does not activate the application. The disposable fixture alone subsequently enables its synthetic login to test operations. Production password provisioning, existing-role reconciliation and operator launcher remain pending. A failed production connection/commit must be reconciled, never blindly rerun.

The 47-check isolated suite adds five cases: wrong database OID refusal, full rehearsal rollback, rollback of newly created roles after a later SQL failure, disabled-login verification and rejection of reinstallation over existing roles. Existing permission, atomic batch, replay, expiry, delivery and restart checks now exercise this shared installer. Only disposable PostgreSQL containers are touched; fake HTTP means no Paytm/Telegram requests. The previous accepted 42-check report does not establish acceptance of these new installation cases.

Run outside market hours after pulling the latest code:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\TestPaperPersistenceBundle.ps1 -ApprovalDelivery
```

Docker Desktop must be running. The existing MarketBrain application may remain running; this does not rebuild or restart it. One paper-delivery JSON contains the result and can be collected by the existing automation queue. The suite itself is not yet a remote execution job; do not claim it was submitted automatically. Expect several minutes, with progress and bounded stage timeouts.

Market-hours work: real fresh reference and ACCEPT revalidation after installation/custody/launcher gates are complete. REJECT, expiry, unauthorized-callback and replay logic can be exercised with fixtures off-hours. Tomorrow's market session alone does not remove the remaining integration prerequisites.

Local validation: 36 Java tests passed in a separate Maven build directory, zero failures/errors/skips; 92 offline PowerShell assertions passed. An initial local rerun encountered editor-generated incomplete bytecode; the separate build recompiles the exact sources and avoids that output collision. The installer also rejects unexpected function execution grants inherited from administrative default privileges. Real 47-check database execution remains pending. [Installer evidence](evidence/paytm-publisher-installer-local-20261125.json).

## Publisher catalog preflight after accepted rehearsal

The new 47-check installer suite is accepted from run8311e17efade (full run identity in evidence): 188.204 seconds, 38 source hashes matched1392ec4, three temporary containers removed. Rehearsal rollback, later-failure rollback, disabled roles and collision refusal passed on actual disposable PostgreSQL. Do not rerun it unchanged.

The next off-hours step is GetPaperWriterPreflight.ps1 -Publisher. This selects publisher-specific role/function names in the standalone read-only catalog inspector, records database name/OID, and checks the twelve required relations, schema and PUBLIC privilege findings. The connection is read-only, repeatable-read, bounded to five seconds per query with row limits, and rolled back. No table contents are read and no role, grant, function or application setting is changed. Existing writer mode remains unchanged.

It uses the existing repository .env and process overrides through a separate Compose project. That is configured-database evidence, not proof that the current running service uses the same target. Reconcile database identity before installation. The existing application database user may lack installation authority: report that finding; do not automatically elevate, revoke permissions or adopt existing roles. Public TEMP and other permission findings require scoped interpretation, not blanket permission removal.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\GetPaperWriterPreflight.ps1 -Publisher
```

Docker Desktop and the configured database must be available. No Paytm login or market hours are needed. This builds only a standalone inspector and leaves the application running. One paper-publisher-preflight JSON is saved; the updated Observe collector can retrieve its allowlisted metadata and source hashes automatically, without raw process logs, expanded environment or credentials. Inspection findings are evidence to review, not automatic installation approval. Production role installation/custody/launcher and real Telegram acceptance still remain.

Local verification: 30 Java tests passed in an isolated Maven output tree, 117 offline PowerShell assertions passed, and collector redaction/hash/newest-selection/malformed-input/early-failure projection tests passed. Generated collector artifact verified within the queue size limit. These do not establish application database catalog acceptance. [Local evidence](evidence/paytm-publisher-preflight-local-20261125.json).

## Catalog configuration timeout correction

Run c22faf688482445382c225f3714a5ac3 stopped before build/catalog inspection: configuration exit -999, timedOut true,30.529s, no stdout/stderr. Later read-only remote version probes passed (Compose0.342s, engine0.084s). This establishes current availability, not the original stall's underlying cause. No PostgreSQL rejection or credential failure was captured.

The launcher now checks engine and Compose independently (60s each), then gives config --quiet a bounded90s with existing10s progress. Failures retain DOCKER_ENGINE_UNAVAILABLE/TIMEOUT, COMPOSE_PLUGIN_UNAVAILABLE/TIMEOUT or COMPOSE_CONFIGURATION_REJECTED/TIMEOUT plus stage/exit/timing/output lengths. No automatic retries, service restarts, credential changes or permission bypass. Collector includes these sanitized fields and can run two bounded read-only version probes after a configuration timeout; it never returns raw native output.155 offline workflow assertions and collector redaction/early-failure tests pass. Rerun the same -Publisher command above; actual catalog acceptance remains pending.

## Accepted publisher catalog and running-container reconciliation (25 November 2026)

Automatic job 0a3907fa-3a03-4d4b-9a86-b657bb1a7073 collected run eda33eeede73479f88f99640dcd4edfa. The configured catalog inspection passed in 102.484 seconds; all seven source hashes match 26eaea6. All twelve tables are present, no publisher role/function collisions or PUBLIC grants requiring remediation were found, and inspector cleanup passed. The sole installation finding is ROLE_PROVISIONING_REQUIRES_AUTHORIZED_ADMIN. Keep the application account restricted; use a separate PostgreSQL administrator for eventual provisioning. No database writes, application restart, broker or Telegram calls occurred.

The next off-hours command binds the same read-only inspector to the single running MarketBrain container's three database environment variables, retains those values only locally, checks its workspace/PAPER mode, rechecks container identity/start time/image and database settings after inspection, and requires database marketbrain/OID 16389 from the accepted report. It restores prior process variables on both success and failure. Ambiguous containers, stopped services, alternate Spring environment overrides and target mismatch stop the run. It does not prove the Spring datasource has no file/command-line override, or uniquely identify a PostgreSQL cluster; those limitations remain for installation reconciliation. The application must be running for this new check. No administrator password is needed.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\GetPaperWriterPreflight.ps1 -Publisher -RunningApplication `
    -ExpectedDatabase marketbrain -ExpectedDatabaseOid 16389
```

One publisher-preflight report is retained and collected automatically on request. A positive runtimeConfigurationMatched means the running container's database environment and the inspected target matched, not that installation occurred. Production installation, dedicated credential custody, operator launcher and real Telegram acceptance remain pending. Local validation: 173 offline workflow assertions plus collector projection/redaction tests passed; generated queue artifact checked. No Java code changed. G1-G6 remains 24/30 (80%): 100/100/80/100/100/0. Do not rerun the accepted 47-check disposable suite unchanged.
## 27 November 2026: running-configuration acceptance and administrator rehearsal

Collected automatically via job 2b94de3f-923b-4028-af9d-51a6b2b235c8: paper-publisher-preflight-20261127-112749-690ac3065fc6.json, SHA256 34E499B1809ABD30070C1E8330F5DA5060A183B22E67E98C1BDF282FFEA5FB30. Runtime configuration matched marketbrain/OID 16389; all twelve required tables, seven source hashes against 3bb8ae9, and cleanup passed. Elapsed 81.814 seconds. The only remaining catalog finding is administrator role-provisioning authority. This accepts container-environment reconciliation, not proof of all Spring configuration overrides or installed publisher permissions.

Next: TestPaperPublisherInstallation.ps1 builds the standalone Java client without replacing the application. It requires the exact accepted preflight SHA256, resolves the single running PAPER container, reuses its existing database URL locally, and prompts once for PostgreSQL administrator credentials. It sends the request through stdin, with no password argument, Docker environment, saved password file or raw native output in evidence. No Windows administrator password or broker login is requested. Credentials necessarily exist temporarily in local process memory.

After the local REHEARSE confirmation, PaperPublisherRehearsal reads the administrator catalog, requires the exact database name/OID and no unresolved catalog findings, invokes the already tested installation engine only in REHEARSE_ROLLBACK mode, then compares the catalog after rollback. It has no commit option. Temporary catalog writes are explicitly reported as requested; application account/order rows are not mutated. It rechecks application container identity/start time/image and database environment. Failed or timed-out attempts are not retried. Only its uniquely named disposable client container is eligible for cleanup; built images are retained. On failure, share/collect the report before another attempt. No HBA, firewall, service, secret custody or application settings are changed.

Run in PowerShell 7 on the spare laptop, with Docker, PostgreSQL and MarketBrain running. Avoid simultaneous schema/role administration during the short rehearsal. No market hours are required:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\TestPaperPublisherInstallation.ps1 `
    -AcceptedPreflightSha256 '34E499B1809ABD30070C1E8330F5DA5060A183B22E67E98C1BDF282FFEA5FB30'
```

The newest publisher-preflight report in C:\MarketBrainData\Review must match that hash; otherwise pass its original path with -PreflightPath. Expected result: PUBLISHER_REHEARSAL_PASSED_INSTALLATION_PENDING. One paper-publisher-rehearsal JSON supports automatic collection. The script itself requires local interactive credentials; it is not an unattended queue operation. Successful rehearsal enables preparation of the explicit disabled-role commit and credential/socket provisioning. It does not install roles, send Telegram or enable trades.

Validation: 60 Java tests passed (15 new rehearsal, 15 existing installer, 30 preflight), 94 mocked rehearsal-launcher assertions, 173 preflight regression assertions, real local stdin/EOF transport, and collector redaction/rehearsal selection tests. No Docker/PostgreSQL execution occurred on the development laptop. The previously accepted 47-check PostgreSQL suite tested the unchanged engine; it does not establish production rehearsal acceptance. G1-G6 remains 24/30 = 80%, with G6 0% until the combined real Telegram batch passes.
## 27 November: administrator rehearsal accepted; disabled installation prepared

Automatic collection job d422bfb3-0304-4fb2-a8b7-39d830848a1f returned paper-publisher-rehearsal-20261127-130549-0d602fa13a3c.json (SHA256 3CBE4E7DDB623512D0540D8EA5E7E49D3CAAEC41AD575CB421FD7E3D8F1D718A). All eight source hashes match e0c127a. Rollback verified, committed=false, loginEnabled=false, application runtime unchanged, cleanup passed. Total 172.217s including build/prompts; Java rehearsal 3.978s. This accepts the real administrator rollback transaction. No persistent publisher installation or Telegram delivery occurred.

InstallPaperPublisher.ps1 now requires that exact accepted rehearsal report. It resolves and rechecks the running container, builds a separate client and sends credentials via stdin as before. Installation confirms a current restorable backup locally, requests INSTALL_DISABLED, repeats the fresh administrator catalog/rehearsal, commits exactly the existing two NOLOGIN/passwordless roles and three publisher functions, and runs a separate read-only verification transaction. The application stays running; avoid concurrent role/schema administration. No user tables, application settings, HBA/firewall, password custody or login activation are changed. No broker or Telegram requests are made.

Readback checks exact target/admin identity, two restricted passwordless NOLOGIN roles, absent role memberships, no schema CREATE exposure, the three exact function signatures/bodies/owners/search paths/language/return types, execute-grant boundaries, and absence of direct publisher table/column writes. It does not certify future credential routing or helper privileges after arbitrary administrator changes. No existing publisher objects are silently adopted by installation. VerifyOnly can inspect the expected disabled state without calling the installer or committing.

Before the process can attempt installation, its checkpoint says UNKNOWN_AFTER_ATTEMPT. A returned commit acknowledgment changes this to COMMITTED even if later readback fails. A timeout or missing response is never interpreted as rollback. Do not rerun installation after an exception; fetch the report and use the same command with -VerifyOnly for reconciliation. The read-only mode requires the accepted rehearsal hash too and does not enable login. Both modes save one paper-publisher-install JSON for automatic collection; credentials stay local.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\InstallPaperPublisher.ps1 `
    -AcceptedRehearsalSha256 '3CBE4E7DDB623512D0540D8EA5E7E49D3CAAEC41AD575CB421FD7E3D8F1D718A'
```

Use PowerShell 7 on the spare laptop with Docker, PostgreSQL and MarketBrain running. Confirm BACKED_UP only if a current restorable database backup exists, then INSTALL_DISABLED; enter PostgreSQL administrator credentials locally. Windows elevation and market hours are not required. Success: PUBLISHER_DISABLED_VERIFIED_CREDENTIALS_PENDING. It clears persistent permission installation only; separate publisher credential/socket provisioning and the authenticated operator launcher remain before the real combined Telegram test.

Local checks: 46 Java tests (16 new verification/commit-outcome tests, 15 existing installation and 15 rehearsal tests), 154 offline installer assertions, collector projection/redaction tests and generated-job consistency. Actual production commit/readback remain untested until the spare run. The shared installation engine and rollback path were previously accepted against real PostgreSQL. G1-G6 stays 24/30 = 80%; G6 remains 0% until its end-to-end real Telegram checkpoint passes.