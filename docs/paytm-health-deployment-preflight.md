Accepted as E271 on 2026-11-15. Continue with [guarded activation](paytm-health-activation.md); historical preflight instructions follow.

# Real deployment preflight after E270

E270 accepts the spare isolated Java health-transport run: 34 JUnit tests including 39 guard assertions, 110.305 seconds, successful cleanup, no application change. All 18 source hashes match 4568724. Evidence: evidence/paytm-java-health-accepted-20261115.json.

## Why this step

The code and isolated tests are ready for deployment preparation. Before changing the running service, collect its actual baseline: the correct Compose stack, existing environment/mount/port/paper-policy contract, available image for rollback, paper ledger state and locked writer. Avoid assuming that a previous container or local .env still describes the running machine.

The script is read-only against the runtime: Docker inspect/image inspect/cp/config, writer STATUS and account overview. No build/up/restart, health publishing, clock change, credential creation or SQL migration. All private Docker inspect/Compose output remains in memory. Existing environment values are temporarily supplied only to the local Compose-config process and restored afterward; secrets and account responses are not written to the report. The artifact records command exit/timing metadata, safe identity, validation booleans and migration differences only.

The current /app/app.jar is copied to a unique Windows temporary file. Migration SQL entries are compared with the checkout using UTF-8 text SHA256 after CRLF normalization; missing/new/changed migrations stop acceptance. No files are extracted from the archive, SQL text is not reported, and the temporary JAR is deleted even on failure. This is comparison of packaged migration resources, not a direct check of database schema/Flyway history. The rollback image is confirmed locally available, not backed up or proven restorable by this read-only check.

Compose rendering uses the three existing files: compose.yaml, compose.paper-storage.yaml and compose.paper-review-memory.yaml. Existing validated environment, paper policy, mounts and port checks are reused. The running container must match this workspace and remain unchanged throughout; account state must match before/after and writer must remain locked. No changes are automatically made to make a failed preflight pass.

## Verification

Nine local fixtures passed: real ZIP/text migration comparison (same text across line endings, changed content, missing/new migration, invalid archive path) and five controller scenarios (pass, migration difference, Compose mismatch, account drift, unlocked writer). Controller fixtures mock system/application calls and verify no mutating Docker operation, secret-free report, temporary file cleanup and process environment restoration. Actual deployment acceptance requires the spare-laptop report.

## Spare steps

Keep Docker Desktop and the existing MarketBrain service running. Run when other maintenance/test jobs are idle. No Pageant/PuTTY or administrator password is needed. Do not manually rebuild/restart or unlock the writer.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmHealthDeploymentPreflight.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-timed-route-0b186b03d92f4f26b55bbc63406f1139.json'
```

Expected HEALTH_DEPLOYMENT_PREFLIGHT_PASSED_ACTIVATION_PENDING. Share the ONE paytm-health-deployment-preflight JSON, even on failure. This provides the baseline for protected credential provisioning and staged deployment; it does not authorize ignoring later drift. Activation must recheck the live baseline and implement rollback. Subsequent actual health publication/rejection/expiry/restart and unattended-reader lifecycle remain pending.

G1 100%, G2 100%, G3 80%, G4-G6 0%; 14/30 = 46.7%. G3.5 remains open until runtime acceptance; no login, quotes, orders or Telegram review are enabled here.
