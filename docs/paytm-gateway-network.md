# Gateway network interruption and application recovery

## Current handoff: recover the reviewed worker, then test the network

**E224, 2026-11-04:** Run `b49f51c3f0db4ad996892fcdcd6b14b7` stopped in preflight after **4.161 seconds**, before any firewall rule, cleanup task or application check. Ten source hashes match83b323d. The worker accepted in E222 subsequently exited with `TRANSPORT_UNKNOWN` after5166.534 seconds (about86 minutes), with four SSH attempts recorded. The task is enabled/idle with result1; the process is absent. Its native SSH error was not persisted, so the historical cause remains unknown. Previous acceptance stays **100/100/20/0/0/0,11/30 (36.7%)**; current gateway health is blocked.

Code review found that exit classification could run before final stderr drained, and some Windows TCP-connect messages were unrecognized. The correction drains the exited native child first, retains bounded structured tags/length/hash (no raw debug text), and recognizes the exact pinned-endpoint TCP `Unknown error` diagnostic. Arbitrary unknown errors, host/key failures, listener conflicts, destination restrictions and TLS failures still block. The [Windows OpenSSH issue](https://github.com/PowerShell/Win32-OpenSSH/issues/2482) documents one possible TCP message; it does not prove that this run encountered it.

Use the command below with **both switches**. It pins E224, verifies the exact stopped worker/files/task/control state under the worker lease, archives seven files and verifies their hashes, updates only `transport.ps1` and its manifest entry, then archives/removes only those reviewed failure markers. The existing task starts once. Only a healthy fresh worker permits the network test to begin. New failures remain captured and trigger durable STOP/task disable; there is no repeated automatic recovery or generic marker reset. No DLL, runner, key, credential, VPS configuration or task registration changes are needed for recovery.

Local verification:282 assertions across the adapter, actual native Windows child/loopback tests,17 recovery workflows, evidence projection,14 network workflows and27 combined collector workflows. Runtime APIs are mocked where stated in [E224 evidence](evidence/paytm-gateway-transport-failure-20261104.json); actual spare recovery is pending. Do not manually clear failure files or rerun the old recovery switches.

E222 accepts task cancellation and recovery: 51.253 seconds total, both processes gone and listener removed in 1.529 seconds, 10.785 seconds quiet, fresh healthy worker, three application checks and unchanged INR 100000 paper account. Together with E213 duplicate-start/persistent-stop evidence, G3.3 closes. Groups are **100/100/20/0/0/0**, **11/30 (36.7%)**. Do not rerun cancellation or its older recovery commands.

E223 prepares the remaining network half of G3.1. Runtime acceptance is pending. A successful reviewed result would close G3.1, moving G3 to 40% and the bounded plan to 12/30 (40%). It does not close other G3 checkpoints or establish broker login/quotes.

## What the next batch does

1. Verify the accepted E222 cancellation receipt, E213 transport/E216 restart receipts, installed hashes, exact task, healthy gateway, locked application and unchanged account. Require all Windows Firewall profiles enabled and no leftover test rules/tasks.
2. Register an independent SYSTEM cleanup task and create a **disabled** test rule. Require the real Windows PowerShell 5.1 worker to remove it and exit successfully. Only then proceed to an actual interruption.
3. Register a second cleanup task, verify its running heartbeat, then briefly block **incoming TCP replies from 130.250.191.137:22 to C:\Windows\System32\OpenSSH\ssh.exe**. The rule applies to any native OpenSSH session to this VPS, not just a particular Windows user. PuTTY and other destinations/programs are outside its scope. No profiles or existing rules change.
4. End only the previously verified gateway SSH child so the replacement connection encounters the block. Require two advancing BACKOFF heartbeats, increased attempt/failure counters, absent listener, unchanged supervisor identity and a failed/locked application request.
5. Remove the exact test rule, verify cleanup-task exit/removal, observe automatic reconnect by the same supervisor with a new child, and confirm the application remains locked. Explicitly rearm the diagnostic route for one TLS HEAD check, then finish locked and compare the account/container again.

The guard uses a monotonic 180-second deadline and a boot trigger; a second launch removes the rule immediately. It attempts cleanup independently if the controller closes. It serializes rule creation/removal with a file lease. Cleanup failures remain visible, with the owned guard retained when needed; this is not a guarantee against OS/Task Scheduler failures. A disabled-rule rehearsal checks the native boundary before introducing an outage. Protected local guard evidence is retained; **only one JSON needs sharing**.

The incoming-reply block avoids manufacturing an outbound socket permission-denial message that could be confused with SSH key rejection. It does not weaken key/host/TLS validation. Missing retries, wrong scope, unexpected worker exit, direct fallback or automatic authority replay fail the batch. After an actual interruption failure, existing cleanup requests durable STOP and disables the gateway task; do not override that state manually.

## Run on the spare laptop

Keep Docker Desktop and the existing MarketBrain application container running. Leave the gateway's failure files and task state intact for the reviewed recovery. Use **PowerShell 7 as Administrator**. No PuTTY/Pageant, reboot, installation, password entry or application rebuild is needed. Keep the window open. Allow roughly 3–6 minutes; startup/reconnect waits are bounded at 120 seconds and outage observation at 75 seconds.

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
& '.\ops\windows\TestPaytmGatewayCancellation.ps1' -NetworkInterruption -RecoverReviewedTransport
```

Expected: `GATEWAY_NETWORK_INTERRUPTION_AND_RECOVERY_PASSED`. Share the printed `paytm-gateway-network-<runId>.json`. It includes timing, guarded-rule/task results, source hashes, retry observations, application checks and account preservation. `taskReRegistered=false` refers to the existing gateway task; `cleanupTasksRegistered` separately counts the two temporary cleanup tasks.

The accepted report files and E224 failure report remain at their original `C:\MarketBrainData\Review` paths. If moved, supply `-CancellationReportPath`, `-TransportReportPath`, `-RestartReportPath` or `-TransportFailureReportPath` with the original bytes. Never edit a report to bypass its hash check.

## Verification and limits

Local tests run the real timer, file lease, JSON reports and cleanup worker in native Windows PowerShell 5.1, with firewall/identity boundaries substituted. Controller workflows exercise the real task/rule construction and validation with Windows runtime APIs mocked. Spare SYSTEM scheduling, native firewall effectiveness and actual VPS reconnect remain unproven until this report is reviewed. No Paytm credentials, token exchange, quotes or orders are tested.

Windows supports program, direction, remote-address and port-scoped firewall rules ([New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule?view=windowsserver2025-ps)). SYSTEM task principal and bounded task settings follow [New-ScheduledTaskPrincipal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal?view=windowsserver2025-ps) and [New-ScheduledTaskSettingsSet](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2025-ps).
