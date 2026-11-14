# Guarded diagnostic health bridge activation

E271 accepts the preflight in 9.244 seconds: all 28 packaged migration resources match source and the account, writer lock, Compose contract and container were preserved. This is not a database schema audit or a completed deployment.

## What this step achieves

Rebuild only marketbrain-service, preserving its existing environment, mounts, ports and paper policy. Generate a separate diagnostic health token and verify its real HTTP authentication boundary. Combine absent/wrong token, unhealthy evidence, replay, challenge expiry and previous-boot rejection tests, with one additional restart. The route remains locked throughout; no healthy evidence, arm, broker login, quote request or trade is submitted. Alerts briefly pause during recreation and restart. Keep other maintenance/test jobs idle.

The controller pins the accepted report, rechecks the exact container/image and all packaged migrations, builds while the old service runs, then checks for source/account/container drift before recreation. Failure after deployment starts triggers a bounded rollback attempt to the retained old image. It verifies ownership before rollback and then account preservation, writer lock and environment. A rollback failure is reported for review; no image or volume is pruned. This is an image/configuration rollback, not database restoration.

The random diagnostic token is generated automatically, never printed, passed as a command argument or written to a Windows secret file. It is stored in the container environment and is visible to Docker administrators. Process environment overrides are restored afterward. Ordinary future Compose recreation without preserving this token disables the diagnostic endpoint; use reviewed deployment workflows. No new password to remember.

## Local verification

35 targeted Java tests passed, including 39 timing-guard assertions and a real application-YAML environment-alias binding regression. Eleven PowerShell fixtures passed: Compose field preservation, actual boundary helper sequencing with mocked HTTP and real expiry wait, receipt validation, deployment success, build failure, deployment failure, boundary failure and refusal to roll back over a foreign container. Fixtures do not prove actual Docker deployment; the spare-machine receipt is required.

## Run on spare laptop

Use PowerShell 7 with Docker Desktop and the current service running. No PuTTY/Pageant or credential entry is needed. The build has a 30-minute deadline; usually allow several minutes. Do not run alongside another maintenance job.

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
& '.\ops\windows\ActivatePaytmHealthBridge.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-health-deployment-preflight-deeca536524746189bda5a0823e43daa.json'
```

Expected: `HEALTH_BRIDGE_DEPLOYED_LOCKED_LIVE_PUBLICATION_PENDING`. Share the ONE `paytm-health-activation-*.json` printed at the end, including on failure. If it fails, do not blindly rerun activation or prune images: the report establishes whether rollback succeeded.

G3.5 remains open. G1/G2/G3/G4/G5/G6: 100/100/80/0/0/0%; 14/30 = 46.7%. After deployment acceptance, real healthy publication and unattended collector lifecycle remain, followed by Paytm login, fresh quotes and Telegram review. This percentage measures accepted Paytm checkpoints, not overall project completion.
