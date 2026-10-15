# Runtime credential and policy verification

E136: this isolated package is now accepted at100%. Do not rerun the historical script below. Proceed only with the [guarded application handoff](paper-runtime-application-handoff.md); never apply the memory overlay manually. E137 permits the bounded real credential handoff with NOLOGIN unchanged, not Telegram publication or review writes.

2026-10-15, E134. Current handoff: one isolated spare-laptop test. E133 authentication acceptance remains valid; do not repeat installation, HBA staging or authentication.

## Fixture startup correction

E135: the first spare run at revision39b1525 stopped after112.116s with `RUNTIME_FIXTURE_NOT_READY`. The image build and isolation checks succeeded. Spring rejected the fixture's9-character dummy pairing code; the real configuration requires at least16. No credential handoff or Linux check receipt completed. The owned fixture stop command succeeded; the failed container was deliberately retained, so cleanupComplete=false is not a cleanup-command failure.

The dummy code is now `SYNTHETIC_PAIR_CODE`. Regression coverage calls the fixture's exact application and property factories, reproduces the old failure, and checks rejection at9/15 characters and acceptance at16. The real validator and real Telegram credentials are unchanged. These tests are in the verifier image's existing build test list, so this defect is now caught before container startup.

The new exact-configuration test failed before the correction. After the correction, the full Java suite passed781 tests across153 suites, with zero failures, errors or skips. No local Docker or real-service execution was performed for this repair. The779-test baseline below is the earlier E134 run, not an additional test total.

Use the script below after pulling the correction. It creates a new uniquely named fixture; do not restart the failed container or prune Docker resources. Share the new single JSON. Passing local regression tests does not establish a successful Linux handoff; package60% and full-roadmap12.4% remain unchanged.

## Purpose and scope

Prove the approved Windows-to-Java credential handoff can unlock, lock and restart safely before involving the real writer password or Telegram proposals. The default application configuration remains off. The candidate `compose.paper-review-memory.yaml` is not deployed by this test and must not be applied independently.

The implementation freezes `PAPER_TELEGRAM_TEST_100S_V1`: lifetime100s, quote age15000ms, slippage50bps, quantity1, worst permitted notional500000paise. ACCEPT remains review-only, never an order, reservation or fill. These limits are enforced exactly for PROCESS_MEMORY mode. Existing file mode remains explicit; memory mode rejects a credential-file setting and cannot silently fall back to it.

The Linux application starts locked. A local `docker exec -i` helper receives the credential on stdin and talks to an owner-only Unix socket in a0700 directory; the socket is0600. Only socket metadata goes on that filesystem, not the password. The secret is stored in a clearable Java buffer; new reads stop after locking, and shutdown/restart requires a new unlock. Identical unlock is idempotent; a different secret cannot overwrite an unlocked one. Stale socket paths and unsafe directory permissions fail closed. No public endpoint, second Telegram poller or Tailscale change is introduced.

Locked callbacks receive an explicit **not processed; retry after local unlock if still valid** acknowledgment. They do not become ACCEPT/REJECT receipts and do not consume the proposal token. The existing poller can advance that acknowledged update; there is no automatic replay after unlocking. SQL-failure cursor retention remains unchanged. Locking prevents new secret acquisition; it does not cancel an in-flight operation or revoke an existing database session. NOLOGIN/session revocation remains a separate database control. An UNLOCKED result proves memory custody only, not database authentication.

Java's [Unix-domain socket support](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/net/UnixDomainSocketAddress.html) provides the local channel. Windows/Docker administrators and the owning container user remain trusted. Memory, dumps and paging are not an absolute secret-protection boundary; [Docker tmpfs may swap](https://docs.docker.com/engine/storage/tmpfs/). The actual credential remains untouched by this package.

## Verification

Local result:779 Java tests across153 suites, zero failures/errors/skips;112 offline PowerShell assertions, including eight fully mocked runner scenarios. The latter cover success, build failure, unknown container-create outcome, unsafe networking, failed fixture, lost unlock acknowledgment, stale restart logs and wrong cleanup ownership. A harmless child process exercises stdin delivery and timeout handling. No local Docker, application database, model or Telegram call was made.

The spare bundle builds only a verification image, then runs a disposable network-none, read-only container. It creates a synthetic password and exercises Windows CurrentUser DPAPI protect/unprotect, stdin handoff, repeated unlock, explicit lock, new unlock, container restart and locked startup. A per-JVM boot ID prevents old Docker logs from counting as restart evidence. Each native process has a deadline; long processes print heartbeats. Runtime progress, source hashes, individual checks, timings, final state and cleanup are captured in one JSON.

The fixture has18 unique checks, rerun after restart without counting them twice: actual Spring memory-mode locked startup with no database attempt; exact policy; no publisher/executor bean; locked callback with no dial; private socket permissions; initial status; unlock; identical replay; different-secret refusal; malformed-secret refusal; socket-only filesystem; explicit lock; unlock after lock; owned-socket removal on shutdown; fresh-context locked state; stale-path refusal; broad-permission refusal; and zero database attempts across the suite.

Only a uniquely labelled owned fixture can be stopped/removed. Successful containers are removed; built images and evidence remain. Failed fixtures are preserved with stop requested after ownership verification. Do not prune other Docker resources. Unknown unlock outcomes trigger a best-effort lock, not automatic re-unlock. A cleanup failure prevents a passing report.

## Run on the spare laptop

Use PowerShell7 with Docker Desktop in Linux-container mode. No administrator database password is needed. This does not rebuild, restart or deploy the real application.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7, then rerun.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Repository must be clean. Preserve local changes; do not reset them.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\TestPaperRuntimeReviewBundle.ps1'
```

Share only the printed `C:\MarketBrainData\Review\paper-runtime-review-<timestamp>-<id>.json`. Required success status: `ISOLATED_RUNTIME_HANDOFF_PASSED_ACTIVATION_PENDING`; final stateLOCKED, cleanupComplete=true, both fixture reports pass with different boot IDs. Runtime evidence is pending until this file is reviewed; a successful mocked local run is not Linux runtime proof.

## What passing enables next

After report review and owner acceptance, prepare the guarded real application deployment/unlock and restricted proposal-publication authority. Then verify actual private Telegram ACCEPT/REJECT, duplicate/opposing clicks, expiry, fresh-price/risk blocks, durable receipts and independent unchanged-account reconciliation. Neither this fixture nor the candidate overlay grants publication privileges or enables PostgreSQL LOGIN. No actual review proposal is sent now. Paper fills, costs, holdings/P&L, the month-long pilot, numerical validation and live release remain subsequent gates.

Bounded package progress:60% local (D/I/V),40% spare verification/acceptance pending. Full-roadmap12.4% and effective-access review80% are unchanged; do not average these scopes or call them prediction accuracy.
