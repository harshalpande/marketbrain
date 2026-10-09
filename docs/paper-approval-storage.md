# Paper approval storage and key setup

2026-10-09. The preceding delivery rehearsal is accepted: **24/24 checks in 199.542 seconds**, with all 30 source hashes verified (E94). The next authorized batch (E95) attaches approval storage to the existing application and binds a persistent encryption key. **Sending, callback activation, reservations and execution remain disabled.**

## Application changes

V28 promotes the already verified approval/delivery SQL and adds a singleton immutable key-binding record. It does not seed proposals, tokens, notifications or trades, or alter account cash. Normal Flyway startup applies V28 even without the optional storage overlay; key setup remains disabled by default.

The opt-in Compose overlay mounts `C:\MarketBrainData\Secrets\PaperApproval\delivery.key` read-only at `/run/secrets/paper-approval.key`. The key is not placed in environment values, Git or reports. The runner generates 32 cryptographically random bytes only on explicitly requested first installation, using create-new semantics and a private Windows ACL. Existing files are validated and reused, never overwritten. Junction/symlink paths, inherited/broad ACLs, malformed and all-zero keys are rejected. Protect backups separately; machine administrators remain trusted.

The overlay uses long-form `read_only` and `bind.create_host_path: false` so a missing key path is not silently created as a directory. See the [official Compose service-volume reference](https://docs.docker.com/reference/compose-file/services/#volumes).

On explicitly enabled PAPER startup, the application binds a domain-separated fingerprint and encrypted verification probe. It refuses a different key and refuses first binding over unbound existing approval evidence. The binding is immutable: automatic rotation, key replacement and uncertain-delivery reconciliation are **not implemented or authorized**. A lost key requires restoring the original; a reviewed rotation/migration design is still needed before operational approval release.

Setup failures leave approval storage blocked without intentionally failing unrelated data-collection startup. A private, no-store GET at `/api/v1/paper/approval/storage` checks the current file against the database binding. It never creates the binding or enables an action. The existing read token permits inspection only. This route is not exposed by the UI proxy. No callback bean, publication endpoint, dispatch worker, broker endpoint or model dependency is registered.

Database access uses the existing application datasource, with primary-key/limited existence queries and bounded statement/lock timeouts. A dedicated least-privilege approval writer role, complete operating risk policy and real transport acceptance remain release gates. This package must not be described as completed least-privilege execution integration.

## One handoff for two stages

The runner first confirms a pristine attached account and a restorable database backup, then performs **12 new disposable PostgreSQL checks** (10 preparation, two restart). These cover V28 preservation, encrypted probe validation, replay, wrong keys, concurrent setup, absent binding, orphan evidence, immutable binding, rollback and restart recovery. Failure prevents application deployment. Prior accepted delivery checks are not rerun on spare.

After these pass, it creates/reuses the private key and requires confirmation that a secure recoverable copy exists. It then builds/recreates only service/UI with the explicit overlay. Existing database/volumes are retained. Startup can create the key-binding metadata; postflight GETs are read-only. Existing background schedules and notifications remain configured as before and can resume after restart; this storage feature does not initiate them.

Postflight checks anonymous denial, no-store status, the unchanged INR100,000 account/ledger, the portal proxy boundary and `STORAGE_KEY_VERIFIED_ACTIONS_DISABLED`. The runner restores caller environment values afterward; the container retains its read-only mount through ordinary restarts. Future recreation must use this overlay again. Do not use older deployment scripts for this storage configuration.

## Spare laptop command

Use PowerShell 7 with Docker Desktop running. Have the current paper read token available locally, application jobs idle, and a restorable database backup. Do not share credentials or the key file. **Only type backup confirmations if the backups actually exist.** The runner prompts after creating the key so you can secure a copy before deployment.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) { throw 'Inspect/preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop here.' }
& '.\ops\windows\DeployPaperApprovalStorage.ps1' -Deploy -CreateKey
```

`-CreateKey` is first-install permission, not permission to rotate or replace an existing key. If a key is missing after deployment, restore it rather than regenerating it. An existing key is reused even with this switch. Creation is refused when the current application already exposes the storage status route and the local key is absent.

Expected final status: `APPLICATION_APPROVAL_STORAGE_VERIFIED_ACTIONS_DISABLED`. Share **only the final `paper-storage-application-<id>.json`**. It embeds the isolated report. A subordinate isolated JSON is retained locally for recovery; no need to upload it separately. Both build stages have bounded 30-minute ceilings and progress/heartbeats; these are not expected durations.

If deployment completed but postflight was interrupted, use the same script **without `-Deploy -CreateKey`** for read-only recovery. Do not automatically repeat a failed deployment or delete a key, table or Docker volume. A key prepared before cancellation remains available for reuse. A failed setup needs report review, not a guessed new key.

## Acceptance still pending

Local tests use mocked JDBC/HTTP/Docker/key provisioning; the real isolated migration and application mount/ACL/startup are verified by the spare run. Actual backup restoration is not exercised by owner confirmation. Successful application attachment closes only the storage/key gate. Next comes an explicitly controlled real private Telegram and Upstox review-only test, then approved risk and atomic paper reservation/fill integration. Numerical predictive performance and Paytm real execution remain separate and blocked. Full parent-goal baseline stays **12.4%**.
