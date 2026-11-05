# Native process recovery and 30-minute observation

**Completed and accepted in E234:** Run `2a00177e7fa8499bacc912f6a3b10f02` passed in 1847.099s with 1809.708s observation, 129 observations, one worker/SSH child and zero reconnects. Eight archives, two route checks, account preservation and final locks passed. **Do not rerun this recovery.** Continue with [the session test](paytm-gateway-session.md). Commands below are historical implementation instructions.

**E233, 2026-11-05:** Report `1290fc4e5fc448ac98c749ff437f4a8d` completed in 6.801 seconds. All four source hashes match `07242e7`. Metadata collection is now complete: both Windows executable signatures are valid, their DACLs include Builtin Users read/execute, and all three installed helper hashes match the manifest. Three selected policy-event queries have no matches. Administrator `curl --version` succeeds. These are current metadata observations, not proof of the gateway account's effective access at the earlier failure. The worker remains absent, task Ready/result1, and its first-cause native error5 is preserved.

## What changes and why

The old native wrapper did not identify whether start, wait, drain or stop failed. Its `finally` block could also overwrite the original exception with a cleanup exception. The new wrapper records a bounded operation label and preserves the first exception plus separate cleanup metadata. The runner and evidence reader retain those fields without copying raw stderr, exception text, arguments or credentials.

The wrapper also handles an owned child exiting between timeout and termination: a failed `Kill` is tolerated only if a separate bounded wait confirms that child has exited. A still-live or unobservable child continues to fail closed. [Microsoft documents that Framework Process.Kill can throw when a process is terminating or has already exited](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.kill?view=netframework-4.8). This supports handling the race; it does **not** establish that the old gateway failure was this race. No permissions, antivirus policies, task account, SSH restrictions, proxy destinations or timeouts are relaxed.

## One batch on the spare laptop

Keep the laptop awake and connected for approximately **35 minutes**. Docker Desktop and the existing MarketBrain application container must be running for application lock and account checks. No application rebuild, PuTTY, Pageant, password entry, VPS change, sign-out or restart is required.

Run in **PowerShell 7 as Administrator**:

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
& '.\ops\windows\RepairPaytmNativeProcess.ps1'
```

The batch:

1. Verifies the exact accepted diagnostic receipt, transport receipt, installed hashes, stopped task/process, controls, free listener, exclusive worker lease and absence of a session checkpoint. It verifies the running application remains locked and records the existing paper account.
2. Copies and hash-verifies eight existing files into an administrator-protected archive: native DLL, runner, manifest, two controls and three worker evidence files. The archive also retains the replacement sources and compiled DLL. Only the receipt-matching failure can be recovered.
3. Compiles the new native DLL through inbox Windows PowerShell 5.1 and checks local `curl --version` before replacement. Sets STOP, replaces DLL/runner, updates and verifies the manifest, checks the original markers again, then removes only the archived markers. It restores LOCKED and starts the existing task **once**.
4. Verifies fresh transport readiness and the application's explicit diagnostic route, then observes the same worker for at least 1,800 seconds. Heartbeat and listener ownership must advance; reported transport health must be recent. A gap greater than 45 seconds between worker observations fails the batch, so suspension cannot count as observed uptime. This exceeds the prior 1,387.3 seconds of recorded uptime. Console progress/checkpoints appear approximately every 30 seconds, with bounded health waits between them. A final observation occurs after the complete interval.
5. Checks the application route again and verifies final application/writer locks and unchanged account/container state. Failure after recovery begins attempts STOP and disables the owned task; no automatic retry. New failure details are retained.

Expected success: **NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED**. Share only the printed `paytm-native-recovery-<runId>.json`. Protected archives remain on the spare laptop; do not share their entire directory. If the batch fails or is interrupted, share the JSON before rerunning. A partial replacement or newer failure will not be automatically reset. Closing/killing the controller can prevent its final cleanup; recovery after such an interruption requires review of the saved checkpoint and current state.

This uses the existing gateway key for transport authentication and the local private application read token for verification. No Paytm broker credentials, login, quote requests or orders are enabled. Root HEAD HTTP503 may still prove reachable TLS transport; it is not API readiness. Successful observation establishes the measured interval only, not continuous availability or the historical root cause.

## Verification and next milestone

**398 local assertions passed:** native process 12, recovery 69, controller 47, bootstrap 41, failure evidence31, native transport11, session187. Coverage includes deterministic exited/live denied-stop cases, preservation of first failure, actual child timeout, real PS5 compilation/curl probe, actual runner operation recording, eight controller outcomes, 18 recovery workflows, changed markers/files/task state, partial install, failed start, interrupted health, final lock failures and input/archive preservation. Controller success uses an accelerated local fixture; privileged runtime boundaries are mocked. Neither the actual gateway-account recovery nor the 30-minute spare observation has been accepted yet.

Groups remain **100/100/40/0/0/0; 12/30 (40%)**. No checkpoint increment for this engineering correction. On acceptance, return to G3.4 sign-out/full shutdown verification. Remaining security-negative and clock/health tests, Paytm login, quotes and Telegram review remain open.
