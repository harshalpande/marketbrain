# Gateway task cancellation and application recovery

## Current handoff: inspect the saved worker failure

**E218, 2026-11-04:** Cancellation run `f7a8cfeeafc04b2a9892d685d7324943` stopped in preflight after3.145s with `STARTUP_WORKER_FAILURE_PRESENT`. All seven source hashes match be19124 CRLF bytes. No cancellation or application request occurred. The existing worker has at least one saved failure marker; the report omitted its contents, so the underlying cause and current worker state are unknown. Do not clear either marker or rerun cancellation yet.

The corrected collector includes bounded structured worker diagnostics on failures. Its new `-InspectOnly` mode reads the fixed `blocked.json`, `startup-failure.json`, `status.json` and control files, records task definition/state/result and native process observations, and samples the heartbeat twice. Arbitrary exception messages, stderr, key material and unknown fields are omitted. Missing, unreadable, oversized and malformed files remain distinguishable. An advancing heartbeat is not treated as proof of healthy TLS or listener ownership.

Use PowerShell7 as Administrator on the spare laptop:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Preserve local changes before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -InspectOnly
```

Expected status: `WORKER_FAILURE_DIAGNOSTICS_CAPTURED`. This means evidence was captured, not that gateway health or cancellation passed. Share the one printed `paytm-gateway-cancellation-*.json`. It does not use Docker or contact the VPS, import keys, clear latches or change/start/stop tasks. It writes only its report and acquires the existing controller lock. The failed test did not establish current account/writer state. Previously accepted G1/G2 checkpoints remain100/100; current gateway health is unconfirmed and G3 remains0 pending recovery and testing.

The execution instructions below describe the original cancellation batch and are on hold until the saved failure is reviewed.

E216 accepts the Windows restart report in 14.623 seconds: a new background worker, application TLS route, preserved INR100000 cash and final locked authority. G2 is now100% (five accepted checkpoints). No further restart, installation, key import or VPS change is needed for the next batch.

## Why this test is next

E213 already proved duplicate-start suppression and persistent STOP. A cooperative STOP differs from cancelling the Windows scheduled task while its SSH child is running. This batch checks that native process/job containment removes both the worker and SSH child, releases the loopback listener, and makes an armed application diagnostic fail closed. Connectivity recovery must not restore the application's previous permission to issue requests.

This is the missing cancellation portion of G3.3. Its successful runtime result, together with E213, can close that checkpoint. It does not close network interruption, wrong-host/key/TLS negatives, independent logoff/cold power loss or clock-health gates. The accepted restart report records13 attempts and433 cumulative outage seconds; these counters are retained as observations, with causes unknown, not a continuous-uptime claim.

## What the single batch does

1. Pins the accepted restart and transport reports by SHA256; checks installed hashes, ACLs, exact task/principal/settings and existing application/account/writer lock.
2. Checks a healthy advancing worker and a real credential-free application TLS HEAD response.
3. Retains verified native worker/SSH process handles, then cancels only `MarketBrain-Gateway-Supervisor-v1` using Task Scheduler. No task registration/settings, key, VPS, firewall or Docker changes.
4. Allows at most20 seconds for both processes to exit, task to become idle and port18889 to have no listener. It does not trust a stale `status.json` after abrupt termination.
5. Requires the still-armed application's next HEAD to fail and lock; verifies no surviving listener or unrequested task restart during a ten-second observation window.
6. Explicitly starts the existing task once, requires a new worker and child identity, checks that the application remains locked, then explicitly rearms the bounded HEAD diagnostic and verifies TLS.
7. Locks the application again; confirms unchanged account, container, image and application boot. Saves one JSON with results, timings and captured metrics.

A failure after cancellation attempts a durable STOP and disables/stops only the reviewed task, then reports whether that cleanup succeeded. Do not re-enable or clear STOP yourself on failure. Preflight failures leave the gateway unchanged. Normal exception/console interruption paths run final cleanup; forcibly killing PowerShell or powering off cannot guarantee finally-block execution. Keep the test window open until it prints its result.

## Run on the spare laptop

Keep Docker Desktop and the existing MarketBrain application running. Use **PowerShell7 as Administrator**. No PuTTY, Pageant, password or reboot is required. The accepted files remain at their original `C:\MarketBrainData\Review` paths; the downloaded `(1)` filename is not used on the spare laptop.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Preserve local changes before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayCancellation.ps1'
```

Allow roughly1–3 minutes on a healthy system; individual waits are bounded and shown with progress. Expected status: `GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED`. Share the **one `paytm-gateway-cancellation-*.json`** printed by the script. This briefly interrupts the gateway, not Windows networking or the MarketBrain application. It uses no Paytm credentials and enables no orders, reservations or fills.

Local verification is recorded in E217. Local mocks validate decisions, cleanup and report handling; they do not substitute for actual Task Scheduler termination/job cleanup on the spare laptop. Accepted percentages remain **100/100/0/0/0/0** until the runtime report is reviewed.
