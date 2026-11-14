# E249: stability accepted; do not rerun recovery

**Current E249, 2026-11-14:** Sustained gateway stability accepted: 1803.187 seconds, 144 observations, same worker and SSH child, one connection attempt and zero recorded transport failures. Both application routes, unchanged INR100000 paper account and final locks passed. [Next: fresh sign-out and full shutdown/startup verification](paytm-gateway-session.md). Groups 100/100/40/0/0/0; 12/30 (40%), unchanged until G3.4 passes. Broker authentication and quotes remain untested.

The E248 recovery instructions below are historical.

# E248: successful diagnostic capture; sustained stability next

Accepted November14,2026: `10103fb0a49f4d8583abf08375aef49f`, SHA256 `6BE34F12BD1147453E7DA3841C1588FAC4B2E7634DF7A3FA708553863485E0E4`. All ten source hashes match e453746 with CRLF. Capture completed at303.812 controller seconds; total325.229s. There are55 ready-state samples, zero sampled outages, zero dropped samples, one recorded connection attempt and zero recorded transport failures. Sampled latest-probe elapsed values range488–1706ms (repeated observations are not independent requests). Same worker and SSH child persisted in sampled evidence. Final stop/disable verification, unchanged paper account and application/writer locks passed. The22,202-byte report fits the unchanged64KiB bound.

This accepts diagnostic collection and resolves the report-overflow verification. It is not a30-minute continuous-stability pass, not proof that the historical network problem is permanently fixed, and not broker readiness. Root HTTP503 means a completed TLS/HTTP exchange only. `workerDiagnostics` is intentionally captured before the final stop; its Running state does not contradict the later `failureStopVerified=true` flag. The next preflight rechecks actual stopped state.

## Next run

`-TlsStabilityRecovery` requires this exact accepted receipt and the stopped worker `c338666a731548d79efb93642071222d`/PID2924. It checks disabled owned task, STOP control, absent process, free listener, no new failure/checkpoint and reviewed installation/source hashes. With a lease held it copies and verifies ten files, rechecks state, archives old status, enables the task and starts once. Installed transport code, manifest and keys remain unchanged.

The existing controller then verifies the initial application diagnostic route, observes the same worker for at least1800 seconds, checks fresh/advancing status with no observation gap over45 seconds, and verifies the final application route, paper-account preservation and application/writer locks. It does not count transient BACKOFF as healthy or loosen readiness timeouts. Failure requests STOP and disables the task, retaining evidence. Success leaves the transport running and application access LOCKED for the next reviewed session test.

## Spare-laptop script

Keep the spare laptop awake and connected for about35 minutes. Docker Desktop and the existing MarketBrain application container must be running. No PuTTY, Pageant, rebuild, sign-out or shutdown.

Open **PowerShell7 as Administrator**:

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
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -TlsStabilityRecovery
```

Expected `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`, mode `TLS_STABILITY_AFTER_ACCEPTED_CAPTURE_NO_CODE_REPLACEMENT`. Share the printed `paytm-native-recovery-*.json`, including if it fails. Do not rerun automatically against changed worker state.

## Local tests and progress

152 local assertions:97 archive/unchanged-code/single-start/idle-gate assertions and55 controller assertions across eight workflows. Privileged runtime APIs mocked; actual archives and hashes exercised; successful controller time shortened only in test copy. Actual spare stability remains pending.

G1/G2 100%, G3 40%, G4–G6 0%;12/30 (40%) bounded readiness, unchanged. After accepted stability, resume G3.4 sign-out/full shutdown validation. No broker login, quote access or orders enabled by this run.
