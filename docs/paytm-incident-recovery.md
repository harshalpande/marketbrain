# E244: incident collection accepted; one controlled recovery

**Superseded after failure:** Do not rerun this adapter. Use [E245 TLS phase diagnostics](paytm-tls-phase-diagnostic.md).

The incident report `93a4edc9f423415184a3243b2f76c414` is accepted as collected evidence. SHA256 `841B4F91E312C866E98E50DBA61DA15C055ED00BA375A9B36FCC5432ECA41827`; both source hashes match a686a40 with CRLF. The VPS read196 journal entries without reported truncation: one gateway key acceptance/session opening, zero classified throttling or penalty entries. No disconnect is recorded in this selected window. Absence of a logged event is not proof that it could not occur. `19:02:22+05:30` represents `13:32:22 UTC`; JSON timestamp conversion did not change the instant. Historical clock offset and exact cross-host connection match remain unknown.

## Why this run

The previous recovery initially passed TLS, then failed during reconnect and stopped safely. Existing diagnostics are installed; there is no demonstrated authentication failure or justified SSH-policy fix. Start that installation once under observation to establish current stability. This is a controlled recovery test, not a root-cause fix. No repeat of historical journal collection, code compilation, key import or VPS configuration change.

The new `-IncidentRecovery` adapter requires the exact accepted report, disabled owned task (completed/terminated result), STOP control, no old process/listener, no new failure/checkpoint, and the reviewed worker identity. Existing installation/ACL/hash checks remain. The accepted agent/native-phase diagnostic source versions must be installed. It holds the worker lease, copies and hash-verifies ten files, rechecks state, then archives the old status, sets LOCKED, enables the task and starts once. The controller retains the existing30-minute observation, application TLS, account-preservation and final-lock requirements. Failure after mutation invokes existing STOP/disable cleanup and retains evidence. No weakened health timeout or automatic second run.

Successful recovery leaves the supervised transport running with application access LOCKED. A successful30-minute interval does not prove uninterrupted future operation. Failure must be reviewed before another attempt; this adapter cannot replay against a new worker instance.

## Run on the spare laptop

Keep Windows awake and connected for about35 minutes. Docker Desktop and the existing MarketBrain application container must be running. No PuTTY or Pageant action, rebuild, sign-out or restart is needed.

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
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -IncidentRecovery
```

Expected `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`, with `recoveryMode=AFTER_SSH_INCIDENT_NO_CODE_REPLACEMENT`. Share the one `paytm-native-recovery-*.json` printed, including on failure. Original reviewed incident JSON and the accepted managed-transport receipt must remain in C:\MarketBrainData\Review (the wrapper checks both). Root HTTP503 can prove TLS transport only, not broker login/data readiness.

## Verification and progress

199 local assertions:97 adapter assertions across six archive/start scenarios and eight idle-gate scenarios;55 controller assertions across eight incident-mode workflows;47 existing controller assertions across eight workflows. Actual archives and hashes are tested, privileged runtime APIs mocked, successful soak shortened only in a test copy. Actual spare-laptop stability remains pending.

Accepted checkpoints unchanged: G1 100%, G2 100%, G3 40%, G4/G5/G6 0%;12/30 (40%) bounded Paytm readiness, not whole-project completion. G3.4 sign-out/full shutdown remains pending until recovery is reviewed. No broker credentials, orders, reservations or fills enabled.
