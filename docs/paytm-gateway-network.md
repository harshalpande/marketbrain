# Gateway network interruption and application recovery

**Current E230, 2026-11-05:** The session baseline stopped after **0.383s** at `STARTUP_WORKER_FAILURE_PRESENT`; all seven source hashes match `dc1ea47`. A saved worker-failure marker blocks the next stage, but the report omitted its contents, so the cause and current worker health are unknown. No session baseline, task/power change or application/account check was completed. [Next: read-only worker inspection](paytm-gateway-session.md#current-handoff-read-the-saved-worker-failure), one JSON; do not sign out, shut down, clear markers or retry the baseline. The collector now includes bounded worker diagnostics automatically for worker failures. E228 network acceptance remains valid at its recorded scope; groups **100/100/40/0/0/0, 12/30 (40%), no increase**. Account/lock flags in this failed run mean unverified, not a proven balance change.


**Historical E228, 2026-11-05:** Network interruption/recovery accepted in **84.761s**; all 11 source hashes match `5ba324a`. Actual replacement SSH denial produced advancing BACKOFF; the same worker reconnected on attempt 3 (23s recorded outage). Both temporary rules/tasks were removed; 3/3 application route checks, no automatic rearm, final application/writer locks and unchanged INR100000 account passed. **G3.1 closes: groups 100/100/40/0/0/0, 12/30 checkpoints (40%, +3.33 percentage points).** This measures the bounded Paytm plan at capture, not whole-project completion or current uptime. Do not rerun recovery/network. [Next: sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases; runtime acceptance remains pending. Login, quotes, remaining security/health checks and Telegram review stay open. Root HTTP503 remains transport-only evidence.

## Historical E227 handoff (completed; do not rerun): preserve input evidence while saving progress

**Historical E227, 2026-11-05:** Run `d69d38db5d544107bd5859fed8462d22` stopped after **5.083 seconds** with `HOST_NETWORK_RECOVERY_RECEIPT_INVALID`. The input's actual SHA-256 matched the expected E226 hash, and all 11 source hashes match `ea69e3e`. No recovery, firewall rule or cleanup task started. The account remained INR 100000 and application/writer locks passed. The three saved worker-failure projections, lengths and timestamps are identical to E226; the gateway remains blocked/stopped/disabled.

**Root cause reproduced:** `Save-Report` used an unqualified `$path`. PowerShell resolved it to the calling recovery function's `$Path` input parameter, so saving progress replaced the reviewed input receipt with the new in-progress report. Its hash had already been checked; the subsequent read then rejected the overwritten contents. Earlier workflow tests replaced that boundary and did not carry the real Path argument, so they missed the destructive interaction. The same unqualified timer/report references could also select helper-local values.

The collector now binds its output path, timer and report explicitly to its script scope. A regression runs the actual receipt validator, reader and collector writer together with the original E226 bytes. The previous collector fails the input-preservation check; the corrected one preserves input bytes and ignores caller-local Path, clock and report variables. All recovery-mode fixtures now pass real receipt-path parameters and verify unchanged input hashes.

The original uploaded E226 diagnostic is included at `ops/windows/reviewed/paytm-network-e226.json`, byte-identical with SHA-256 `3AC00E888E53B308D910EB889ABDCAE674917171D497240952C4C39FFBBD5977`. Git line-ending conversion is disabled for these reviewed JSON snapshots. It contains diagnostic/account metadata and no credentials or raw private-key material. This replaces no spare-laptop file: preserve the overwritten copy as evidence. The collector defaults to the repository snapshot; **do not pass the old C:\MarketBrainData\Review E226 path**.

**Use `-NetworkInterruption -RecoverReviewedNetworkFailure` below.** The existing exact-state recovery remains applicable because this attempt did not change the installed adapter or saved worker failure. It verifies the task/control/process/listener, installed hashes and all three failure files, checks both firewall stores and scheduled tasks for leftovers, verifies a seven-file archive, applies the already-tested verbose TCP-denial correction, and starts the existing task once. It removes only the unchanged reviewed failure markers after archiving. New failures remain recorded and stop the batch; earlier archives remain untouched.

E226's separate SSH classification defect is already reproduced: the 245-character verbose stderr matches its captured hash exactly. The parser correction handles both the terminal and debug TCP denial while preserving real key/host/listener/destination failure handling. That adapter update has not yet run on the spare laptop because the collector stopped first.

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

The E226 input now comes from the reviewed repository snapshot. Leave other accepted reports in `C:\MarketBrainData\Review`; if moved, pass their original bytes using `-CancellationReportPath`, `-TransportReportPath` or `-RestartReportPath`. Do not edit reports or restore the overwritten file manually.

## Evidence and progress

[E227 evidence](evidence/paytm-gateway-checkpoint-isolation-20261105.json) records the reproduced progress-writer defect and corrected input preservation. E226's parser correction and E225/E222 historical acceptances remain valid at their stated scope. Accepted groups remain **100/100/20/0/0/0**, **11/30 checkpoints (36.7%), change 0 percentage points**. This is the bounded Paytm readiness plan, not whole-project completion or current uptime.

A reviewed successful network batch can close G3.1, moving G3 to 40% and the plan to 12/30 (40%). Login, quotes, remaining failure tests and Telegram review stay pending.

**239 local assertions passed** across 35 combined collector workflows and 19 recovery workflows. Regression uses real pinned input bytes, the real receipt validator/reader and the real collector checkpoint writer. It demonstrates failure with the previous collector, then preservation of input hashes and isolated timer/report/output state with the fix. Recovery fixtures also test marker/archive/source drift and failed-start cleanup; Windows runtime APIs are mocked. Actual privileged recovery, firewall effectiveness and VPS reconnect require the spare run. No broker credentials, quote requests or trades are involved.
