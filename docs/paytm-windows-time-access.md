# Windows Time access diagnosis: no VPS retry

## Reviewed outcome and next action

E162: owner follow-up `11fea1e34d3a41e6b3dc10893178311c` completed capture in **198.117 seconds**. Elevation/confirmation now passed. VPS identity/configuration/stopped-state checks matched; APT index refresh succeeded in **5 seconds**, simulation succeeded with **70 upgrade candidates**, and corrected `tinyproxy-bin` query returned `1.11.2-1`. No package installation or proxy activation occurred. The prior elevation handoff problem is resolved for this run.

Windows Time was **Stopped / Manual**. `sc.exe start W32Time` failed with **OpenService error 5 (access denied)** despite passing the elevated-process guard. Resync was never attempted. Clock comparison remains outside the collection window. This is not an NTP-server timeout or a failure to approve UAC. The exact service-right/token/policy cause is not yet established; do not claim a corrupt service or reset permissions from this evidence alone.

Windows checks the calling token against the service security descriptor when opening a service. `SERVICE_START` is a specific permission distinct from administrator membership. See Microsoft's [service access rights](https://learn.microsoft.com/en-us/windows/win32/services/service-security-and-access-rights) and [OpenServiceW contract](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openservicew). The next diagnostic observes this access check; it does not call StartService.

## What this package does

- Reuses the explicit UAC launcher, then runs a **Windows-only, read-only** inspection. No PuTTY, Pageant, clipboard exchanges, VPS requests, rebuilds or application restart.
- Requires the exact reviewed E162 report hash before collecting diagnostics. Queries seven fixed items: W32Time status/configuration/security descriptor/triggers, time configuration/status, and only the W32Time Group Policy registry subtree.
- Runs an isolated PowerShell child to open/close four local W32Time handles requesting QUERY_CONFIG, QUERY_STATUS, READ_CONTROL and SERVICE_START individually. Captures each right/mask/error and enabled-administrator status in parent and child. It never calls service start, changes a token, resets ACLs or grants permissions.
- Each of seven native queries and the probe child has a 30-second process deadline. A pathological run may take around four minutes plus bounded output/cleanup waits; progress and process heartbeats remain visible. Normal local queries should be much quicker, but no timing guarantee is made.
- Saves one JSON with partial observations on denied queries/timeout/invalid child output. No automatic retry or repair. Stopped W32Time queries may fail normally; missing policy can return registry exit 1. These are observations, not corruption proof.
- Service SDDL can contain local/domain SIDs; policy/configuration can contain internal time-server names. No credential source is inspected. Review before public sharing.

Expected end state is `TIME_ACCESS_CAPTURED_REPAIR_REVIEW_PENDING` or, if the child cannot be collected, `TIME_ACCESS_PARTIAL_REVIEW_REQUIRED`. Neither means clock synchronization or repair succeeded. An allowed start handle also does not prove the service can actually start or synchronize.

## Complete spare-laptop handoff

Use ordinary PowerShell 5.1 or 7. Existing PowerShell 7 must be installed/discoverable. No VPS login or gateway key is needed. The file below is the **latest follow-up** report, not the original operations snapshot.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
$evidence = 'C:\MarketBrainData\Review\paytm-operations-followup-20261022-203631-11fea1e34d3a41e6b3dc10893178311c.json'
if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) { throw 'Latest follow-up report missing.' }
& '.\ops\windows\StartPaytmWindowsTimeAccess.ps1' -OperationsEvidencePath $evidence
```

Approve Windows UAC; watch the **new administrator PowerShell 7 window**. Collection starts automatically because it is read-only: no SYNC_AND_REFRESH, START-TEST, STOP or SERVER_READY response. Share its ONE `paytm-windows-time-access-...json`. Do not repeat the old VPS refresh or try service-permission resets.

## Verification and remaining work

E163: **74 assertions**, nine mocked full workflows cover access denial, allowed handle, failed queries, child admin mismatch, timeout, malformed output, failed child, missing elevation and incorrect input evidence. C# probe compiled; a real local development-machine read-only probe returned allowed query/read-control handles and denied start handle under a non-admin token. This verifies the collection path, **not the spare laptop cause**. Existing 22 UAC launcher and 44 follow-up assertions pass. No service start/security/clock changes or VPS operations ran locally.

Next: interpret service access evidence, prepare the narrow repair justified by it, then verify actual Windows synchronization. Separately review the 70 VPS candidates and backup/recovery/restart requirements before any package installation. Unattended key/task/proxy provisioning, Paytm login/quotes and Telegram review remain blocked from activation; accepted main application-route 8/8 remains intact. No whole-project completion percentage is increased for this diagnostic.
