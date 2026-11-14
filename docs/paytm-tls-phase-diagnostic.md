# E245: HTTPS phase diagnostic after repeated recovery failure

Reviewed November14,2026. Receipt `7c7bced74095402285b8cb199f472802`, SHA256 `B6B496859A0CB49C34EDC8EE9341622295635228300FA89BB05DAE0115487D0A`, failed after86.719s. The initial application TLS route passed. Three TLS probes timed out with curl exit28, proxy CONNECT200 and no final HTTP response; one captured timeout took4094ms. Worker sequence38 advanced to42 in BACKOFF/PROXY_UNAVAILABLE. STOP/disable cleanup, final application locks and unchanged INR100000 account passed. This is not evidence of an SSH authentication failure. The specific reason for the HTTPS stall remains unknown.

## Correction and purpose

The old wait helper reported HEARTBEAT_TIMEOUT whenever the requested ready state was not reached, even when BACKOFF heartbeats advanced. It now reports REQUESTED_STATE_TIMEOUT for a different published state. Actual absent/nonadvancing heartbeat timeout remains distinct. No timeout limit is increased and no unhealthy transport is promoted.

The next run captures five minutes of existing worker activity rather than immediately aborting when it enters BACKOFF. It installs only the hash-pinned transport diagnostic script and updates its manifest after a verified ten-file archive. Existing SSH pins, identity, destination restrictions, curl4-second connection/6-second total timeouts and8-second native bound remain. The worker records numeric TCP-connect, TLS-handshake-completion, first-byte and total timings plus allowlisted stderr categories. Raw stderr, URLs, credentials and key contents are not retained. Timing identifies the last observed phase; it does not by itself establish the cause.

The exact latest receipt, reviewed stopped worker identity, disabled owned task, STOP control, free listener, absence of new failure/checkpoint and installed hashes are required. Older recovery adapters are not applicable. One start only. Five-second sampling accepts CONNECTING/BACKOFF as diagnostic evidence, not health; a45-second nonadvancing heartbeat, a new worker, security latch or scope drift fails collection. At the end the controller always requests STOP/disables the owned task, including after successful collection. Application and writer locks and account preservation are verified. No broker credentials or orders enabled; application network readiness is not retested by this diagnostic.

## Spare-laptop script

Docker Desktop and the existing MarketBrain container must be running. Keep the laptop awake and connected for about5–7 minutes. No PuTTY, Pageant, sign-out, shutdown or Docker rebuild.

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
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -TlsPhaseDiagnostic
```

Expected successful collection: `TLS_DIAGNOSTICS_CAPTURED_GATEWAY_STOPPED_REVIEW_REQUIRED`. `soakPassed` remains false intentionally: this is not a stability acceptance. Share the one printed `paytm-native-recovery-*.json`, also on error. Do not run the older incident recovery or session test afterward. The next remedy depends on the recorded phase; do not relax certificate checks or health criteria to obtain a pass.

## Verification and progress

321 local assertions:75 TLS patch/archive/idle-gate checks,9 fake-clock capture assertions across seven workflows,42 TLS parsing/policy/redaction checks,47 diagnostic controller and47 existing controller assertions,67 managed-transport assertions,31 evidence-projection assertions,3 timeout-classification checks. Runtime APIs are mocked locally; archives, hashes and selected native PowerShell paths are exercised. Runtime TLS cause is still unproven.

G1 100%, G2 100%, G3 40%, G4/G5/G6 0%;12/30 (40%) bounded Paytm readiness. No new checkpoint accepted. G3.4 session tests and broker login remain paused.
