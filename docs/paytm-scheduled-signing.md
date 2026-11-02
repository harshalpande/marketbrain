# Gateway scheduled-account signing verification

Current 2026-11-02: E198 accepts key custody and pinned authentication. G2 is **60% (3/5)**. Do not rerun account creation or key import. E199 prepares the next bounded prerequisite for G2.4: prove that Windows Task Scheduler can use the existing agent key under the dedicated account, without an interactive console or a private key file.

## What the batch does

1. Binds to the exact accepted custody JSON hash; rechecks account/SID/ACLs, enabled account, running agent, custody manifest and the previously installed helper hashes/public identity. Refuses residual encrypted staging or an existing probe task.
2. Creates a uniquely named administrator-protected worker folder and one temporary **disabled** task. Uses the existing gateway Windows password through the Windows API, with Password logon and Limited run level. No automatic trigger, restart or wake policy. Task Scheduler manages the registration credential; it is never written to source, command arguments or reports. The API requires a transient managed password string; memory erasure is not claimed.
3. Checks the registered action, account, task settings and worker hash before enabling and demand-starting it once. Uses built-in Windows PowerShell5.1, avoiding per-user PowerShell7 installation dependencies; no execution-policy override.
4. The worker requires the correct non-admin SID and background session0, verifies absence of the staged private key and expected agent identity, then runs two independent `ssh-add -T` signing processes. No key import/removal, SSH connection, listener or broker call.
5. Records worker evidence and the native Task Scheduler result. A90-second controller deadline and120-second task execution limit bound the run. On success, disables and removes only this run's exact task and confirms its absence. On failure, disables/stops the owned task where its definition still matches and retains it and files for review. Changed task definitions are not overwritten or removed. A retained registration may retain its Windows-managed credential until reviewed removal.

One shareable `paytm-scheduled-signing-*.json` embeds the worker result, source hashes, elapsed times, task-result code, cleanup and unchanged-authority flags. Public worker/source evidence remains under the unique protected directory; no recursive cleanup. The existing agent key, original encrypted export and PPK remain untouched. On a failed or interrupted run, share the report and do not rerun or reset the account. A failed task may be retained disabled; hard task termination is not proof of production descendant-process recovery.

## Current next step: inspect the retained task (E200)

The supplied 12:17 run stopped in 2.119 seconds with `SCHEDULE_PREVIOUS_PROBE_REVIEW_REQUIRED`. All five source hashes match commit 5e73a05 with CRLF checkout bytes. Custody revalidation passed; this run did not register/start a task, stage files or request a password. It does not tell us which earlier probe remains or why that earlier run stopped.

Run **inspection only** below. It reads up to 20 matching tasks, checks their definitions and worker source, and captures bounded, whitelisted worker/original report summaries from the same review directory. It creates one new evidence JSON and does not start, stop, disable or remove tasks, change credentials, import keys or contact the VPS. Missing/mismatched evidence is reported explicitly. Inventory capture is not signing acceptance; share it before attempting another signing run.

## Run on the spare laptop

Open **64-bit PowerShell7 as Administrator**. No PuTTY, Pageant or SSH passphrase is required. Keep the main window open until it prints the report path.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7 -or -not [Environment]::Is64BitProcess) {
    throw 'Use 64-bit PowerShell 7 as Administrator.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Preserve local changes and stop for review.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayScheduledSigning.ps1' -InspectExisting `
    -CustodyReportPath 'C:\MarketBrainData\Review\paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json'
```

No password or confirmation is requested in inspection mode. Expected result: `SCHEDULED_PROBE_INVENTORY_CAPTURED`. Share the printed single JSON, including on failure. Keep existing task/files and account intact. The original signing mode (without `-InspectExisting`) remains available but is not the current handoff; its retained task must be reviewed first.

E200 local validation: 124 assertions across 17 mocked workflows, including empty inventory, matching retained task with original failure, source/definition drift, wrong-run report rejection, and arbitrary secret-field exclusion. Native task definition construction is checked without registration in Windows PowerShell 5.1. Actual scheduled execution and credential access remain unverified on the spare.

## Acceptance and remaining work

Passing proves background signing in a real Password-logon scheduled task at the time tested, not cold-boot persistence or continuous recovery. It clears a prerequisite for the production supervisor. It **does not close G2.4 by itself**: the production runner, scheduled startup, monitored forwarding and cleanup still require implementation and runtime acceptance. Managed VPS lifecycle is G2.5. G3 later covers real interruption, logoff/reboot, persistent stop and no-fallback tests. No new percentage is awarded for this preparation.

G1/G2/G3/G4/G5/G6: **100/60/0/0/0/0**. This is Paytm readiness, not total MarketBrain completion or profitability.

Primary implementation references: [Task principals](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal), [task registration](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask), [task settings](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset). Local mocks cannot establish the spare's Task Scheduler rights or runtime credential access.
