# Gateway sign-out and full shutdown/startup verification

**Current E233, 2026-11-05:** Corrected native evidence completed in **6.801s**, four sources match `07242e7`. Both executable signatures and metadata are complete; three installed hashes match and selected policy queries are empty. The gateway is still stopped; original native operation remains unproven. [Next: archived native-process correction, one restart and 30-minute observation](paytm-native-recovery.md). Cleanup preserves the first failure and records native operations; a denied stop is ignored only after confirmed child exit. 398 local assertions pass; actual gateway-account recovery and soak remain pending. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**.

**Historical E232, 2026-11-05:** Native capture completed in **13.116s**, four sources match `d372adc`, and all three installed helper hashes match their manifest. Three selected event queries returned no matches; administrator curl version succeeded. Both executable metadata rows failed with `CommandNotFoundException`, so the success label did not establish complete collection. [Corrected read-only collection](paytm-native-failure.md) explicitly loads inbox Windows modules, records the metadata stage and rejects missing fields; 117 local assertions include actual PS7-to-PS5 metadata checks with discovery disabled. Worker remains stopped; original native error5 cause unconfirmed. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**; session testing remains on hold.

**Historical E231, 2026-11-05:** Worker inspection completed in **3.16s**; all five source hashes match `2ce584c`. The E228 worker later stopped at a native Windows **Access denied (5)** exception during the observation loop, after 1387.3s recorded uptime. Source line77 points to the curl health-check wrapper; the exact denied native operation is not captured. Task enabled/Ready/result1, process absent, no advancing heartbeat, no session checkpoint. [Next: bounded native/event evidence](paytm-native-failure.md), one read-only report; no marker reset, ACL change or gateway restart. Session testing stays on hold. Accepted groups remain **100/100/40/0/0/0, 12/30 (40%), no increase**; current health is blocked.


## Completed E230 handoff: read the saved worker failure

**E230, 2026-11-05:** Baseline run `1d7c34178a544a958a6a7b04244afc4b` stopped in **0.383 seconds** at `STARTUP_WORKER_FAILURE_PRESENT`. All seven source hashes match `dc1ea47`. The installed-source/control checks preceded the saved-failure guard; worker/session observation and application/account checks were not reached. No baseline checkpoint was created by this attempt. The report does not reveal which failure marker exists or its underlying error. Its false account/lock flags mean unverified in this run, not evidence of lost cash or unlocked authority.

The previous collector did not include the saved failure details. The shareable report now allows up to 64 KiB for combined phase observations and diagnostics; protected checkpoints retain their 16 KiB limit. It now adds bounded, redacted marker/control/task/process/SSH evidence when worker gates fail. `-InspectOnly` reads that evidence independently of accepted input receipts or healthy installation gates. It does not parse, replace or advance a session checkpoint, start/stop the gateway, change controls, contact Paytm or access the application/account. Missing/unreadable files remain explicit; an advancing heartbeat alone is not reported as healthy transport.

**This inspection completed in E231. Do not repeat it; use the native/event handoff linked above. The three session phases remain on hold.** Use PowerShell 7 as Administrator. No Docker, PuTTY, reboot or credential entry is required for this read-only inspection.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\TestPaytmGatewaySession.ps1' -InspectOnly
```

Expected: `SESSION_WORKER_DIAGNOSTICS_CAPTURED`. Share the single printed JSON. This means diagnostic capture completed, not gateway recovery. Do not delete `blocked.json`/`startup-failure.json`, clear STOP, enable/restart the task or rerun old recovery commands. The next action depends on the captured cause. Existing session checkpoints, if any, remain untouched; do not resume them after this source update without review.

E228 remains accepted as historical runtime evidence. Current worker health is unresolved. Groups remain **100/100/40/0/0/0**, **12/30 (40%)**; G3.4 has not advanced.

E228 accepts the network batch in 84.761 seconds: all 11 source hashes match `5ba324a`, a real replacement SSH connection was denied, the same worker reconnected with a new child, both temporary rules/tasks were removed, and the account and application/writer locks passed. The installed verbose TCP-denial correction is now accepted. **Do not rerun the exact-failure recovery or network test.**

G3.1 is accepted. Groups are **100/100/40/0/0/0**, **12/30 checkpoints (40%, +3.33 percentage points)**. These are Paytm readiness checkpoints, not whole-project completion, profitability or current uptime.

## Purpose and limits

This next batch addresses G3.4 using the existing installation. It collects one baseline, verifies that the session-0 gateway survives Windows user sign-out, then verifies a fresh gateway worker after owner-performed full shutdown/startup. Each phase verifies locked application/writer authority, the same paper account/container/image, an explicitly armed diagnostic TLS route and final locking. No gateway task start, reinstall, credential import, broker login, quote or order operation is performed by the collector.

The native read-only query records a hash of the controller user's SID, Windows session ID and token AuthenticationId. Microsoft defines AuthenticationId as identifying the token's logon session ([TOKEN_STATISTICS](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_statistics)). A new terminal in the same logon is insufficient. The logoff phase requires the same user and Windows boot, a changed logon ID, owner confirmation of actual sign-out, and the same background worker with advancing heartbeat. This is not a complete audit of every interactive session or every moment of availability.

The boot phase requires owner confirmation of full shutdown, a new OS boot, a fresh worker started before collection, unchanged installed files/account, and a new application boot. Physical power-off is owner attested; the script does not prove abrupt power-loss tolerance or automatic Docker startup before login. Do not pull the power cable or force shutdown. Docker Desktop may need opening and the existing application container may need starting after login; this does not invalidate gateway startup proof and must not be confused with fully unattended application availability.

Only a reviewed successful final report can close G3.4 (G3 60%; plan 13/30, 43.3%). G3.2 security-negative cases and G3.5 clock/health/no-fallback acceptance remain open. G4 login, G5 quotes and G6 Telegram remain downstream. The HTTP root 503 is still transport evidence only.

## Session phases (on hold until the current worker failure is reviewed)

Schedule this when MarketBrain jobs are idle; save other work first. Keep the same Windows user for every phase. Use **PowerShell 7 as Administrator**. No PuTTY, Pageant or application rebuild is needed. Allow about 10-15 minutes including your sign-out and startup; each native observation is bounded and gateway waits are at most 120 seconds. Use the same checkout for all phases: do not pull updates midway.

### 1. Baseline

Keep Docker Desktop and the existing application container running.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\TestPaytmGatewaySession.ps1' -Phase Before
```

Continue only on **BASELINE_SAVED_AWAITING_SIGNOUT**. The script saves a protected checkpoint and prints the report path. Save work and use Windows Start menu > your user > **Sign out** (not Lock or Switch user). Sign back into the same account. Do not manually start/reinstall the gateway or load its key.

### 2. After sign-out

Open Docker Desktop and start the existing MarketBrain application container if needed. Open a new **PowerShell 7 as Administrator**:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
& '.\ops\windows\TestPaytmGatewaySession.ps1' -Phase AfterLogoff `
    -ConfirmSignedOut -ConfirmNoManualGatewayStart
```

Continue only on **LOGOFF_PASSED_AWAITING_FULL_SHUTDOWN**. Save all work and ensure collection/training jobs are idle. Then run this separate command to shut down the laptop:

```powershell
shutdown.exe /s /t 0
```

This uses the documented shutdown command without `/hybrid` or forced application closure ([Microsoft command reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown)). Wait until the laptop powers off, then power it on normally and sign into the same user. Do not manually start the gateway task.

### 3. After startup

Open Docker Desktop and start the existing MarketBrain application container if needed. Open **PowerShell 7 as Administrator**:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
& '.\ops\windows\TestPaytmGatewaySession.ps1' -Phase AfterBoot `
    -ConfirmFullShutdown -ConfirmNoManualGatewayStart
```

Expected: **GATEWAY_LOGOFF_AND_FULL_BOOT_PASSED**. Share the single printed `paytm-gateway-session-<runId>.json`. It retains the baseline, logoff observation and each phase's locks/account/route/timing proofs. Private `session-checkpoint.json` is operational state and need not be shared.

On failure, share the same report. Do not repeat the baseline or delete the checkpoint. A failed phase preserves the last successful protected checkpoint; for example, if Docker was stopped after boot, start the existing application and retry **AfterBoot only**, without another shutdown. Completed checkpoints/reports are preserved on accidental reruns. Source/installation changes between phases stop verification for review.

Accepted input files are the E228 network report and E213 managed-transport report under `C:\MarketBrainData\Review`. If moved, use `-NetworkReportPath` / `-TransportReportPath` with their original unedited bytes in every phase. No earlier failed report is required.

## Local verification

[E229](evidence/paytm-gateway-session-local-20261105.json): 143 assertions across 19 workflow scenarios plus six native Windows session checks (149 total). Workflow tests use the real collector and atomic checkpoint files with privileged runtime APIs mocked; native read-only tests exercise the actual Windows PS5 token query from PS7. Local tests do not accept G3.4. A conservative report constructed with real worker fields measured 14,504 bytes within the 16,384-byte bounded writer.

E230 correction verification: 187 assertions across 22 collector scenarios plus 30 existing failure-reader assertions (217 total). The actual redacted reader and atomic writers are exercised with privileged OS APIs substituted. Inspection preserves all fixture state files and an existing checkpoint byte-for-byte, bypasses absent receipt files, and does not claim account/lock health. Combined reports over 16 KiB are supported; oversized output leaves the previous report intact. The underlying spare worker cause remains pending.
