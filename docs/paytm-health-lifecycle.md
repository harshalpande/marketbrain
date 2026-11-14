# Runtime health expiry, recovery and revocation

**E275, 2026-11-15:** Lifecycle test stopped before lifecycle began: first collection failed and publication took 8.339 seconds, exceeding the unchanged eight-second freshness budget. Unhealthy submission rejected and final revocation/lock confirmed. Original failing phase was not retained; no specific network cause is claimed. Collector/publisher now retain safe phase/error/exit metadata and independent windowExceeded. 48 local checks passed. Rerun [lifecycle test](paytm-health-lifecycle.md); no rebuild. G3 80%, overall 14/30 (46.7%).


E274 accepts 3/3 fresh publications in 1.962-3.253 seconds each, with final revocation, account/writer/container/time-service preservation and key cleanup. Total 248.185 seconds includes human prompt time. All 12 script hashes match 34962b5. Root HEAD 503 remains transport-only evidence, not authenticated API readiness.

## Combined next test

Use the existing live-publication controller with -LifecycleChecks and the pinned E274 report. Following three baseline rounds, it publishes fresh health and explicitly arms the credential-free diagnostic route. It sends no HEAD while armed. After 32 seconds without publishing, a HEAD and re-arm must both be blocked with HEALTH_STALE_OR_CLOCK_RESET. It then publishes fresh health, proves status/HEAD remain locked until explicit arm, revokes health with an unhealthy submission, and confirms HEAD/re-arm are blocked again. Finally it locks the route, and the outer controller again revokes and checks final lock.

The 30-second server health TTL is shorter than the 100-second diagnostic lease; this verifies health expiration independently of lease timeout. Fresh observations are collected again after expiry, never reused from files. The script does not change Windows/VPS clocks, deploy/restart the application, install a task or use broker credentials. Orders stay disabled. Run alone: another diagnostic publisher could refresh health and invalidate the expiry test. Partial lifecycle observations are checkpointed; loss of the controller process cannot guarantee finally cleanup, so server expiry remains the bound.

## Local checks

Six lifecycle fixtures exercise actual HTTP/receipt validation with a modeled remote guard: success, stale bypass, recovery auto-arm, failed revocation, boot change and failed fresh publication. Nine controller fixtures include real shared Docker discovery/checkpoint helpers with mocked external calls, publication failure/cleanup cases and lifecycle integration success/failure. These 15 fixtures do not substitute for the deployed runtime test.

## Spare laptop

Keep Docker, the application and managed gateway running. In Pageant, load the original administrator PPK for marketbrain-admin; enter its passphrase only there. No PuTTY commands are needed. Run in PowerShell 7:

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
& '.\ops\windows\TestPaytmLiveHealthPublication.ps1' -LifecycleChecks `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-live-publication-20261115-031735-9ca1d951d69c491eb1d03043b00c5e28.json'
```

Type HEALTH-CHECK in PowerShell when ready. Allow about a minute after that prompt, including the visible 32-second wait. At the end review Pageant cleanup, removing only the administrator key added for this test if no other session needs it; keep its encrypted PPK. Type KEY-REVIEWED. Share the one JSON printed on success or failure.

Expected LIVE_HEALTH_LIFECYCLE_PASSED_UNATTENDED_PENDING. No rebuild or restart required.

G3 remains 80% pending accepted runtime lifecycle evidence and unattended collector custody/operation. Total 14/30 (46.7%); G1/G2 100%, G4-G6 0%. Notify the owner explicitly when G3 reaches 100%. No promised fixed retry count: failures must be evaluated, and unattended operation is still not implemented by this test.
