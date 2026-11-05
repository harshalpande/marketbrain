# Gateway sign-out and full shutdown/startup verification

**Current E234, 2026-11-05:** Native recovery and 30-minute observation accepted: **1847.099s total, 1809.708s observation, 129 observations**, all six source hashes match `60cc983`. Eight-file archive verified, one start, same worker/SSH child, zero transport failures/reconnects; both application route checks, final application/writer locks and unchanged INR100000 account pass. Original historical native operation remains unknown. [Next: baseline, actual Windows sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases. A missing application-checkpoint callback was caught locally and corrected before handoff. No recovery/network repeat. Groups remain **100/100/40/0/0/0, 12/30 (40%)**; G3.4 closes only after its final runtime report passes.

**The native recovery is accepted. Do not rerun it or the network test.** The instructions below are the current next step.

## Purpose and limits

This next batch addresses G3.4 using the existing installation. It collects one baseline, verifies that the session-0 gateway survives Windows user sign-out, then verifies a fresh gateway worker after owner-performed full shutdown/startup. Each phase verifies locked application/writer authority, the same paper account/container/image, an explicitly armed diagnostic TLS route and final locking. No gateway task start, reinstall, credential import, broker login, quote or order operation is performed by the collector.

The native read-only query records a hash of the controller user's SID, Windows session ID and token AuthenticationId. Microsoft defines AuthenticationId as identifying the token's logon session ([TOKEN_STATISTICS](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_statistics)). A new terminal in the same logon is insufficient. The logoff phase requires the same user and Windows boot, a changed logon ID, owner confirmation of actual sign-out, and the same background worker with advancing heartbeat. This is not a complete audit of every interactive session or every moment of availability.

The boot phase requires owner confirmation of full shutdown, a new OS boot, a fresh worker started before collection, unchanged installed files/account, and a new application boot. Physical power-off is owner attested; the script does not prove abrupt power-loss tolerance or automatic Docker startup before login. Do not pull the power cable or force shutdown. Docker Desktop may need opening and the existing application container may need starting after login; this does not invalidate gateway startup proof and must not be confused with fully unattended application availability.

Only a reviewed successful final report can close G3.4 (G3 60%; plan 13/30, 43.3%). G3.2 security-negative cases and G3.5 clock/health/no-fallback acceptance remain open. G4 login, G5 quotes and G6 Telegram remain downstream. The HTTP root 503 is still transport evidence only.

## Run the three phases in order

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

## Verification and history

**223 local assertions passed:** 216 across 23 workflow scenarios and seven actual Windows boot/logon-query checks. Privileged runtime actions are substituted in workflow fixtures; the local queries do not change sessions or access the gateway.

E234 adds the missing `Save-Report` callback adapter used by the shared application-route helper. The regression now calls the real helper with only its Docker process boundary substituted. Removing the adapter reproduces CommandNotFoundException before a baseline is saved; with the adapter, all session phases checkpoint successfully and private subprocess output is not written to the report. Native local verification also exercises the actual Windows boot-time and logon-token queries. These checks do not simulate a real user sign-out or close G3.4.

Earlier engineering and failure reviews remain in [E229](evidence/paytm-gateway-session-local-20261105.json), [E230](evidence/paytm-gateway-session-inspection-20261105.json), [E233](evidence/paytm-native-recovery-local-20261105.json) and [E234](evidence/paytm-native-recovery-spare-20261105.json). The first baseline attempt had no saved checkpoint. The new baseline still checks the machine's current state and will refuse an unexpected checkpoint or new worker failure.
