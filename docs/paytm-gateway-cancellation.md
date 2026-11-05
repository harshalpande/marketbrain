# Gateway task cancellation and application recovery

**Current E235, 2026-11-06:** Session baseline passed; AfterLogoff stopped after **49.36s** with `HOST_AGENT_UNAVAILABLE` in the background worker. All eight source hashes match `7c9e321` with CRLF. The report does not distinguish an SSH-agent query timeout from a nonzero exit. [Next: read-only service/event evidence](paytm-agent-failure.md), one JSON; preserve the checkpoint and pause sign-out/shutdown testing. Current gateway health is blocked. Groups remain **100/100/40/0/0/0, 12/30 (40%)**, with no new checkpoint accepted.

**Historical E234, 2026-11-05:** Native recovery and 30-minute observation accepted: **1847.099s total, 1809.708s observation, 129 observations**, all six source hashes match `60cc983`. Eight-file archive verified, one start, same worker/SSH child, zero transport failures/reconnects; both application route checks, final application/writer locks and unchanged INR100000 account pass. Original historical native operation remains unknown. [Next: baseline, actual Windows sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases. A missing application-checkpoint callback was caught locally and corrected before handoff. No recovery/network repeat. Groups remain **100/100/40/0/0/0, 12/30 (40%)**; G3.4 closes only after its final runtime report passes.

**Historical E233, 2026-11-05:** Corrected native evidence completed in **6.801s**, four sources match `07242e7`. Both executable signatures and metadata are complete; three installed hashes match and selected policy queries are empty. The gateway is still stopped; original native operation remains unproven. [Next: archived native-process correction, one restart and 30-minute observation](paytm-native-recovery.md). Cleanup preserves the first failure and records native operations; a denied stop is ignored only after confirmed child exit. 398 local assertions pass; actual gateway-account recovery and soak remain pending. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**.

**Historical E232, 2026-11-05:** Native capture completed in **13.116s**, four sources match `d372adc`, and all three installed helper hashes match their manifest. Three selected event queries returned no matches; administrator curl version succeeded. Both executable metadata rows failed with `CommandNotFoundException`, so the success label did not establish complete collection. [Corrected read-only collection](paytm-native-failure.md) explicitly loads inbox Windows modules, records the metadata stage and rejects missing fields; 117 local assertions include actual PS7-to-PS5 metadata checks with discovery disabled. Worker remains stopped; original native error5 cause unconfirmed. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**; session testing remains on hold.

**Historical E231, 2026-11-05:** Worker inspection completed in **3.16s**; all five source hashes match `2ce584c`. The E228 worker later stopped at a native Windows **Access denied (5)** exception during the observation loop, after 1387.3s recorded uptime. Source line77 points to the curl health-check wrapper; the exact denied native operation is not captured. Task enabled/Ready/result1, process absent, no advancing heartbeat, no session checkpoint. [Next: bounded native/event evidence](paytm-native-failure.md), one read-only report; no marker reset, ACL change or gateway restart. Session testing stays on hold. Accepted groups remain **100/100/40/0/0/0, 12/30 (40%), no increase**; current health is blocked.


**Historical E230, 2026-11-05:** The session baseline stopped after **0.383s** at `STARTUP_WORKER_FAILURE_PRESENT`; all seven source hashes match `dc1ea47`. A saved worker-failure marker blocks the next stage, but the report omitted its contents, so the cause and current worker health are unknown. No session baseline, task/power change or application/account check was completed. [Next: read-only worker inspection](paytm-gateway-session.md#current-handoff-read-the-saved-worker-failure), one JSON; do not sign out, shut down, clear markers or retry the baseline. The collector now includes bounded worker diagnostics automatically for worker failures. E228 network acceptance remains valid at its recorded scope; groups **100/100/40/0/0/0, 12/30 (40%), no increase**. Account/lock flags in this failed run mean unverified, not a proven balance change.


**Historical E228, 2026-11-05:** Network interruption/recovery accepted in **84.761s**; all 11 source hashes match `5ba324a`. Actual replacement SSH denial produced advancing BACKOFF; the same worker reconnected on attempt 3 (23s recorded outage). Both temporary rules/tasks were removed; 3/3 application route checks, no automatic rearm, final application/writer locks and unchanged INR100000 account passed. **G3.1 closes: groups 100/100/40/0/0/0, 12/30 checkpoints (40%, +3.33 percentage points).** This measures the bounded Paytm plan at capture, not whole-project completion or current uptime. Do not rerun recovery/network. [Next: sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases; runtime acceptance remains pending. Login, quotes, remaining security/health checks and Telegram review stay open. Root HTTP503 remains transport-only evidence.

**Historical E227, 2026-11-05:** The 5.083s run matched the reviewed receipt hash, then rejected its contents. Root cause reproduced: the checkpoint writer's unqualified path resolved to the helper's input Path and overwrote that receipt. Script-scoped output/timer/report binding fixes this; regression now combines the real reader, validator and writer. [Next: same exact-state recovery using the original byte-pinned repository snapshot](paytm-gateway-network.md), with no manual file restoration. All 11 sources match ea69e3e; no recovery/firewall mutation occurred, saved failure is unchanged, account preserved and application/writer locked. Gateway remains blocked/stopped/disabled. Groups **100/100/20/0/0/0, 11/30 (36.7%), no increase**.

**Historical E222/E223, 2026-11-04:** Cancellation and recovery accepted in 51.253s; all 11 source hashes match bdc162a. Both processes exited and the listener disappeared in 1.529s. A 10.785s quiet interval, fresh healthy worker, 3/3 application checks, unchanged INR 100000 account and final application/writer locks passed. **G3.3 closes: groups 100/100/20/0/0/0, 11/30 checkpoints (36.7%, +3.33 percentage points).** This measures accepted evidence at capture, not continuous health or whole-project completion. Next: [one guarded network-interruption/recovery batch](paytm-gateway-network.md), with a disabled-rule cleanup rehearsal before the real outage. Engineering is prepared; spare acceptance is pending. Do not rerun cancellation/recovery. HTTP 503 remains transport-only evidence; login, quotes and orders remain pending. The original overwritten worker failure remains unknown.

<a id="current-handoff-resume-the-completed-recovery"></a>
## Historical handoff: resume the completed recovery

**E221, 2026-11-04:** Run `c331433dafe242bca2d651c4625866aa` stopped after20.68s with FileNotFoundException when the controller immediately read the first heartbeat. Eleven source hashes match83ac563 CRLF bytes. Backup, runner replacement, manifest update and evidence archiving all succeeded; one start was requested. The later diagnostic sample captured a new CONNECTING worker with identity, signing, private-copy absence and job containment passing. This is not TLS or cancellation acceptance. The report's task-running observation precedes cleanup: final cleanup verified persistent STOP/task disable, unchanged INR100000 cash/revision0 and locked application/writer.

The controller now tolerates only a missing heartbeat file within its120-second wait. For an explicitly requested start, it also waits for dispatch instead of treating an old task result as the new launch's result. Failure markers, malformed/null data, access errors, task exit after launch, stale heartbeat and listener drift still fail. It requires two advancing valid ready snapshots. The earlier tests mocked the wait itself; new regressions exercise the real wait and reader together, including delayed publication and file disappearance during open.

Verification:363 local assertions passed across startup waiting/cleanup, resume, combined cancellation controller and existing transport/recovery regressions. Runtime APIs are mocked; actual spare resumption remains pending.

Use the resume below, **not `-RecoverReviewedLatch`**. It pins this failed report, verifies the existing seven-file archive, installed sources, exact disabled task, STOP control, absent failure markers/listener and exited prior worker under the worker lease. It does not replace files or erase markers. It enables and starts the existing task once, then continues the cancellation/application recovery batch only if healthy. A new fault is preserved; cleanup reasserts STOP and task disable even if task enabling failed.

Keep Docker Desktop and the existing application container running. Open **PowerShell7 as Administrator** on the spare laptop. No PuTTY, Pageant, reboot, password or application rebuild is needed. Run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 using Run as administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Preserve local changes before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -ResumeReviewedRecovery
```

Allow roughly3–5 minutes when healthy. Share the one printed JSON even on failure. Expected success is `GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED`. No broker authentication or orders. Accepted groups remain100/100/0/0/0/0,10/30=33.3%, until the resumed runtime result is reviewed. G3.3 closure would move G3 to20% and the bounded Paytm plan to11/30=36.7%.

<a id="current-handoff-recover-once-and-test-cancellation"></a>

## Historical E220 handoff: recover once and test cancellation

The update below has already been applied on the spare laptop; use E221 resume above.

E220, 2026-11-04: inspection `8c0d2d14cb304f9493a08f87ba281250` completed in **3.802s**, with all eight source hashes matching c1718eb CRLF bytes. The task is Ready, enabled, exact-definition verified, last result1; recorded worker PID6692 no longer exists and its heartbeat did not advance. All three saved files report `TRANSPORT_PREVIOUS_FAILURE_REVIEW_REQUIRED`. The original runner replaced the first failure during a subsequent launch. The initial cause is therefore unknown; there is no evidence here proving a new network, key or broker error.

The corrected runner retains the first startup and blocked files, while status describes the latest attempt. The recovery below pins this diagnostic and the accepted transport/restart receipts. It checks the application before recovery, validates installed sources/ACLs/task and the exact reviewed evidence, holds the controller and worker leases, and verifies an archive of the three evidence files, runner, manifest and controls. It sets STOP, replaces only the reviewed runner and manifest hash, archives the exact three work files, and makes **one fresh start attempt**. No task registration, key import, password, VPS configuration or application deployment occurs.

If the new worker passes health checks, the same batch performs task cancellation, owned-process/listener cleanup, application failure locking, deliberate restart and explicit diagnostic rearm. The final account/container/writer checks still apply. A post-mutation failure attempts persistent STOP and disables/stops the exact task. A partial update or a newer failure cannot be reset by repeating the recovery flag. Backups remain locally for review; only one JSON needs sharing. Do not manually remove failure files or enable a task after failure.

Local verification: **312 assertions** across native PS5 bootstrap/relaunch,17 recovery workflows,18 combined controller workflows, failure evidence, cancellation rules and existing restart rules/workflows. OS-boundary mocks do not establish spare-laptop health. Accepted percentages remain **100/100/0/0/0/0**,10/30 (33.3% of the bounded Paytm plan). Successful runtime review can close G3.3: G3 would become20%, overall11/30 (36.7%). That credit has not yet been awarded.

1. Keep Docker Desktop and the existing MarketBrain application container running.
2. Open **PowerShell7 as Administrator** on the spare laptop. No PuTTY, Pageant or reboot is needed.
3. Paste this complete block. Keep it open until the report path appears; allow roughly3–5 minutes on a healthy system.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 using Run as administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Preserve local changes before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -RecoverReviewedLatch
```

Expected successful status: `GATEWAY_CANCELLATION_AND_APPLICATION_RECOVERY_PASSED`. Share the single printed `paytm-gateway-cancellation-*.json`, including on failure. No Paytm credentials, quotes or trades are tested. A root HEAD503 still establishes only the transport/TLS diagnostic boundary, not authenticated API readiness.

<a id="current-handoff-inspect-the-saved-worker-failure"></a>

<a id="current-handoff-inspect-the-saved-worker-failure"></a>
## Historical handoff: inspect the saved worker failure

The E218/E219 instructions below are retained as history and superseded by E220 above.

**E219, 2026-11-04 correction:** Inspection run `c40d3055237f49c6b2e42996ef9e41ea` failed after4.489s with `PropertyNotFoundException` at the diagnostic reader's status access. Eight source hashes match0b722c7. The real application-route import enables StrictMode through `PaperAccountReadReview.ps1`; the old reader assumed optional JSON fields existed and then assumed a failed file read supplied `.value`. This was a collector defect, not a confirmed cause of the original worker failure. It has been reproduced with the actual production imports.

The reader now safely accesses optional fields, always supplies a nullable value slot for file observations, and preserves readable failure markers when status is absent, malformed, scalar, null or sparse. StrictMode remains enabled.92 assertions pass:28 reader assertions with actual production imports and64 controller assertions across15 workflows, including the real reader in inspection/preflight-failure cases. Pull the correction and run the **same InspectOnly command below**; no runtime reset/restart is needed. The underlying worker failure and current health still require the resulting report.

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
