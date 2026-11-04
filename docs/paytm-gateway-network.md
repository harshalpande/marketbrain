# Gateway network interruption and application recovery

## Current handoff: recover the reproduced verbose TCP denial

**E226, 2026-11-05:** The latest run `2ebb314193ad49af954ea8b1eeadbcec` stopped after **7.689 seconds**, before recovery or network changes, with `HOST_NETWORK_RESUME_RECEIPT_NOT_REVIEWED`. All 11 source hashes match `a533f4b`. It preserves the INR 100000 account and final application/writer locks. Its diagnostics show a different, earlier worker already blocked with `TRANSPORT_KEY_DENIED`, no surviving process, STOP control and a disabled task. This latest run created no firewall rules or cleanup tasks; it does not establish cleanup of the intervening earlier run.

The earlier worker's 245-character stderr has SHA-256 `43292094F48E6EB533C45228EB0C423B128D31A54D3E56364EB949F4D4B6FA59`. A reconstruction of the Windows OpenSSH banner, connecting message, debug TCP denial and terminal TCP denial matches both exactly. This establishes the classification defect: the parser excluded the terminal `ssh: connect to host ... Permission denied` line, but treated `debug1: connect to address ... Permission denied` as a key failure. The correction handles both exact endpoint/port lines while preserving genuine authentication, host, listener and destination failures. Tests exercise the full verbose output through the native child adapter and actual retry loop.

The fingerprint mismatch is separate. The old collector did not record the selected report's actual hash/path, so its exact cause is unknown. The new handoff uses **this latest E226 diagnostic**, pinned by hash, instead of depending on the mismatched E225 path. It records selected filename and expected/actual hashes for any future mismatch; hash verification is not removed.

**Use `-NetworkInterruption -RecoverReviewedNetworkFailure` below.** Recovery requires the exact disabled/idle task, STOP control, absent old process/listener, installed adapter hashes and all three saved failure projections/lengths to match E226. It checks both firewall stores and scheduled tasks for leftover network guards before changing the installation. Unknown leftovers stop the operation for review. It verifies a new private seven-file backup, changes only the adapter and manifest, archives/removes only the three unchanged reviewed failure files, and starts the existing task once. New failures stay recorded; earlier archives remain untouched. Do not rerun the older resume/recovery switches or manually clear STOP.

The E225 recovery remains historically accepted. Its inbound test rule did not establish a sustained outage, which is why the current test uses a scoped outbound rule. No new network checkpoint is accepted by E226.

## What the batch verifies

1. Recover the exact reviewed E226 failure as above; verify E222 cancellation, E213 transport and E216 restart receipts, a fresh healthy worker, locked application and unchanged paper account.
2. Require enabled Windows Firewall profiles and no leftover test rules/tasks. Rehearse independent SYSTEM cleanup with a disabled test rule, using the real Windows PowerShell 5.1 worker.
3. Install a temporary outbound block scoped to `C:\Windows\System32\OpenSSH\ssh.exe`, destination `130.250.191.137`, TCP port 22. End only the previously verified gateway SSH child. Other native OpenSSH connections to this same destination are also affected briefly; PuTTY and other programs/destinations are outside the rule's scope.
4. Observe actual failed replacement connections, advancing BACKOFF, no listener and an application request that fails and locks. Verify the rule remains active during this observation.
5. Remove the exact rule and its cleanup task, observe automatic reconnect by the same worker with a new child, verify the application remains locked, explicitly rearm only the diagnostic route for a TLS HEAD check, and finish locked with the same account/container.

An independent SYSTEM guard uses a monotonic 180-second deadline and a boot trigger. A second launch removes the rule immediately; rule creation/removal is serialized with a file lease. Cleanup failures retain the owned guard for review. This is not a guarantee against OS/Task Scheduler failures. Protected local evidence is retained; only **one JSON** needs sharing.

## Run on the spare laptop

Keep Docker Desktop and the existing MarketBrain application container running. Use **PowerShell 7 as Administrator** and keep the window open. No PuTTY/Pageant, reboot, credential entry or application rebuild is required. Allow roughly 3-6 minutes; startup/reconnect waits are bounded at 120 seconds and outage observation at 75 seconds. An ineffective block now stops early instead of exhausting that wait.

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
if ($changes.Count) { throw 'Local changes exist; preserve them before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -NetworkInterruption -RecoverReviewedNetworkFailure
```

Expected: `GATEWAY_NETWORK_INTERRUPTION_AND_RECOVERY_PASSED`. Share the printed `paytm-gateway-network-<runId>.json`. It contains recovery proofs, source hashes, timing, network observations, cleanup results and account/authority checks. `taskReRegistered=false` refers to the existing gateway task; `cleanupTasksRegistered` counts the two temporary tasks.

Keep the original reports in `C:\MarketBrainData\Review`. If moved, pass `-NetworkDiagnosticReportPath` for E226, or the accepted `-CancellationReportPath`, `-TransportReportPath`, `-RestartReportPath`, with their original bytes. Never edit a report to bypass its hash check.

## Evidence and progress

[E226 evidence](evidence/paytm-gateway-verbose-denial-20261105.json) separates the immediate report mismatch from the earlier reproduced classification failure. The latter is fixed locally; actual spare recovery and outbound outage acceptance remain pending. E225's completed recovery and E222's cancellation acceptance remain historical evidence. Accepted groups remain **100/100/20/0/0/0**, **11/30 checkpoints (36.7%), change 0 percentage points**. This is the bounded Paytm readiness plan, not whole-project completion or current continuous uptime.

A reviewed successful network batch can close G3.1, moving G3 to 40% and the plan to 12/30 (40%). Login, quotes, remaining failure tests and Telegram review stay pending.

**372 local assertions passed.** Verification covers the exact captured stderr fingerprint, actual Windows child/drain/classification, the real retry state machine, exact-state recovery with real backup/replacement/report files, previous resume regression and combined controller cleanup. Runtime APIs are mocked where stated in E226; actual privileged firewall effectiveness and VPS reconnect require the spare run. No broker credentials, quote requests or trades are involved.
