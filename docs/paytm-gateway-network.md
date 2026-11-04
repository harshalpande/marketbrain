# Gateway network interruption and application recovery

## Current handoff: resume after the ineffective network block

**E225, 2026-11-04:** Run `1c972328b34c4a7e80fb637e05ec8a8c` completed the reviewed transport recovery, including its seven-file archive, adapter update, manifest verification and fresh healthy worker. The network batch then failed with `NETWORK_BACKOFF_NOT_OBSERVED` after **209.908 seconds** total. All 12 source hashes match `e68d47e`. Both temporary firewall rules and cleanup tasks were removed; the account remained INR 100000, reserved cash 0, revision 0, and the application/writer finished locked. Failure cleanup deliberately stopped and disabled the gateway.

The test's inbound rule did not establish the intended sustained outage: the replacement SSH connection became healthy, with attempts increasing from 1 to 2. The final consecutive-failure counter was 0; that counter resets after 60 healthy seconds and is not a cumulative failure count. The collector then waited 75 seconds for BACKOFF. This is a fault-injection defect, not evidence of failed gateway recovery. Exact Windows filtering internals were not captured. An explicit outbound block is the appropriate direction for preventing the replacement connection ([Microsoft firewall configuration](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure)).

The correction uses an **outbound** rule and narrowly classifies the pinned endpoint's TCP `Permission denied` message as network unavailability. SSH `Permission denied (publickey)`, host-key changes, destination restrictions, listener conflicts and other security failures still block. An intentional child exit alone cannot pass: two advancing BACKOFF samples must include a drained, unauthenticated network failure from the current replacement attempt. A replacement connection becoming healthy while the block is expected now fails early with `NETWORK_BLOCK_INEFFECTIVE`. A bounded transition history and final polling observation are saved in the one report.

**Use `-NetworkInterruption -ResumeReviewedNetwork` below.** The new resume path pins E225, verifies the disabled/idle task, STOP control, absent worker/listener, absence of new failure markers, installed sources and all seven previous archive hashes. It privately backs up five current files, updates only the transport adapter and its manifest hash, then enables/starts the existing task once. It preserves all previous archives and current status; it clears no failure markers. New failures stop the batch and retain STOP/task disable. Do not rerun `-RecoverReviewedTransport`, reinstall the gateway or manually clear STOP.

## What the batch verifies

1. Resume the exact reviewed state as above; verify E222 cancellation, E213 transport and E216 restart receipts, a fresh healthy worker, locked application and unchanged paper account.
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
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -NetworkInterruption -ResumeReviewedNetwork
```

Expected: `GATEWAY_NETWORK_INTERRUPTION_AND_RECOVERY_PASSED`. Share the printed `paytm-gateway-network-<runId>.json`. It contains resume proofs, source hashes, timing, network observations, cleanup results and account/authority checks. `taskReRegistered=false` refers to the existing gateway task; `cleanupTasksRegistered` counts the two temporary tasks.

Keep the original reports in `C:\MarketBrainData\Review`. If moved, pass `-NetworkFailureReportPath` for E225, or the accepted `-CancellationReportPath`, `-TransportReportPath`, `-RestartReportPath`, with their original bytes. Never edit a report to bypass its hash check.

## Evidence and progress

[E225 evidence](evidence/paytm-gateway-network-fault-20261104.json) records recovery success and the ineffective fault separately. E224's original native failure remains historically unknown; its recovery is now complete. E222 cancellation acceptance remains valid. Accepted groups remain **100/100/20/0/0/0**, **11/30 checkpoints (36.7%), change 0 percentage points**. This is the bounded Paytm readiness plan, not whole-project completion or current continuous uptime.

A reviewed successful network batch can close G3.1, moving G3 to 40% and the plan to 12/30 (40%). Login, quotes, remaining failure tests and Telegram review stay pending.

Local verification: **415 assertions** across adapter classification (55), actual native child/loopback (9), prior recovery (41), evidence projection (30), network workflows (45), reviewed resume (102) and combined collector (133). Runtime APIs are mocked where stated in the evidence. No elevated real firewall test is available on the development machine; actual outbound fault effectiveness and VPS reconnect must be verified by the spare run. No Paytm credentials, token exchange, quote retrieval or orders are enabled.
