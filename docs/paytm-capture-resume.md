# E247: cleanup confirmed; resume the bounded five-minute capture

**E248 accepted:** Do not rerun this capture adapter. Continue with [sustained stability verification](paytm-tls-stability.md).

The November14 report `48dea31593e345bc95eee1bf4ed94b5b` is accepted as current-state evidence. SHA256 `080D3CBE26AB0872DE413CFB5DDFB481745A822EA6354ECD0C23A20D4BF52D59`; all three source hashes match. Worker `c1fb4e25f96c4e0daca23210ff30a883`/PID3708 is STOPPED at sequence196, elapsed228.818s; task disabled/result267014, control STOP, process absent, no startup-failure or blocked marker. Saved transport counters are one attempt and zero failures. Final recorded probe:621ms native elapsed, proxy CONNECT200, TLS handshake completion442ms and HTTP503. HTTP503 proves a completed TLS/HTTP exchange only, not broker API readiness. This snapshot does not establish an entire300-second observation or independently verify paper balance/application locks.

The reporting overflow stopped the earlier run. Resume with the compact collector; do not repeat installation or reuse the original worker receipt. A new adapter pins this exact current-state receipt and rechecks the stopped worker/sequence, disabled task, STOP control, installed hashes/diagnostic source versions, absent failure markers/checkpoint and free listener. It holds the worker lease, copies and verifies ten files, rechecks them, archives the old status, enables the owned task and starts once. Installed source, manifest and keys are preserved.

The fixed collector records five minutes of new observations with the existing64KiB report bound. It records CONNECTING/BACKOFF as diagnostic samples, never as health passes. The old worker cannot count as the new capture. Finalization always stops/disables the gateway, verifies application/writer locks and unchanged paper account, and writes one report. This is a diagnostic rerun, not continuation of the old timer or a30-minute stability acceptance. A rare serialization fallback may produce an additional small `.final.json` to preserve cleanup results.

## Spare-laptop steps

Keep the laptop awake and connected for5–7 minutes. Docker Desktop and the existing MarketBrain application container must be running. No PuTTY, Pageant, code rebuild, sign-out or shutdown.

Run **PowerShell7 as Administrator**:

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
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -TlsCaptureResume
```

Expected `TLS_DIAGNOSTICS_CAPTURED_GATEWAY_STOPPED_REVIEW_REQUIRED`, mode `TLS_CAPTURE_RESUME_NO_CODE_REPLACEMENT`. Share the one printed `paytm-native-recovery-*.json`. It is expected to stop the gateway even on successful capture. Share failure evidence before another attempt; no automatic reset against changed worker state.

## Local verification and completion

77 adapter assertions (real archives/hash preservation, privileged task APIs mocked),58 controller assertions across nine workflows (including final size failure/cleanup fallback),10 diagnostic assertions across eight fake-clock workflows. The report-size regression reproduces the old overflow and completes200 real atomic writes; final test report35,274 bytes, under65,536. These establish engineering behavior, not spare-laptop runtime acceptance.

G1/G2 100%, G3 40%, G4–G6 0%;12/30 (40%) bounded Paytm readiness, unchanged. Recorded short-run transport behavior improved over the preceding failing run, but no new readiness checkpoint is closed by this snapshot.
