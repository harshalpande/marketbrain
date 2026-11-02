# Gateway scheduled-account signing verification

Current 2026-11-02: E198 accepts key custody and pinned authentication. G2 is **60% (3/5)**. Do not rerun account creation or key import. E199 prepares the next bounded prerequisite for G2.4: prove that Windows Task Scheduler can use the existing agent key under the dedicated account, without an interactive console or a private key file.

## What the batch does

1. Binds to the exact accepted custody JSON hash; rechecks account/SID/ACLs, enabled account, running agent, custody manifest and the previously installed helper hashes/public identity. Refuses residual encrypted staging or an existing probe task.
2. Creates a uniquely named administrator-protected worker folder and one temporary **disabled** task. Uses the existing gateway Windows password through the Windows API, with Password logon and Limited run level. No automatic trigger, restart or wake policy. Task Scheduler manages the registration credential; it is never written to source, command arguments or reports. The API requires a transient managed password string; memory erasure is not claimed.
3. Checks the registered action, account, task settings and worker hash before enabling and demand-starting it once. Uses built-in Windows PowerShell5.1, avoiding per-user PowerShell7 installation dependencies; no execution-policy override.
4. The worker requires the correct non-admin SID and background session0, verifies absence of the staged private key and expected agent identity, then runs two independent `ssh-add -T` signing processes. No key import/removal, SSH connection, listener or broker call.
5. Records worker evidence and the native Task Scheduler result. A90-second controller deadline and120-second task execution limit bound the run. On success, disables and removes only this run's exact task and confirms its absence. On failure, disables/stops the owned task where its definition still matches and retains it and files for review. Changed task definitions are not overwritten or removed. A retained registration may retain its Windows-managed credential until reviewed removal.

One shareable `paytm-scheduled-signing-*.json` embeds the worker result, source hashes, elapsed times, task-result code, cleanup and unchanged-authority flags. Public worker/source evidence remains under the unique protected directory; no recursive cleanup. The existing agent key, original encrypted export and PPK remain untouched. On a failed or interrupted run, share the report and do not rerun or reset the account. A failed task may be retained disabled; hard task termination is not proof of production descendant-process recovery.

## Current next step: capture the Windows launch error (E201)

The supplied 12:51 inspection completed in 3.016 seconds. All five source hashes match e699817 CRLF checkout bytes. One retained task, run6b3bcee5eac24157aa38b858b96ae253, is disabled with the expected definition and unchanged worker source. Its original report timed out in RUN_BACKGROUND_SIGNING_CHECKS (131.447 seconds total). Windows LastTaskResult267011 / 0x41303 means the task has not yet run; no worker result exists. The historical `taskStarted=true` records successful return from the start-request API, not observed worker execution. The cause of the launch failure is not established. Account/key recreation is not justified by this evidence.

Run **inspection only** below. It now adds the task's last-run metadata and Windows events: up to32 exact-task Scheduler events and32 account-specific Security4625 batch-logon failures over the last seven days, per task. Account events are correlated by name/logon type/time, not proof of a particular task's failure. Only IDs, timestamps, numeric error codes and instance IDs are shared; arbitrary event messages, arguments and credentials are omitted. Disabled logs are still queried for retained history. Empty/unavailable logs and result caps are explicit; no logging policy changes or claim that events must exist.

The existing task/source/original-report checks remain. One new JSON is created; no task start/stop/removal, credential change, key import or VPS contact occurs. Inventory capture is not signing acceptance. Share the JSON to determine the targeted correction; do not retry signing or reset the account yet.

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

E201 local validation: 137 assertions across the same17 workflows plus event parsing/query fixtures. Tests cover launch codes, exact task binding, batch-logon scope, disabled logs with retained events, empty/access-denied logs, query errors, caps, DTD rejection and omission of arbitrary secrets. Event APIs are mocked locally; no real task/credential/key/network changes. See [Microsoft task status constants](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants) and [task-history troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshoot-scheduled-tasks-not-running).

## Acceptance and remaining work

Passing proves background signing in a real Password-logon scheduled task at the time tested, not cold-boot persistence or continuous recovery. It clears a prerequisite for the production supervisor. It **does not close G2.4 by itself**: the production runner, scheduled startup, monitored forwarding and cleanup still require implementation and runtime acceptance. Managed VPS lifecycle is G2.5. G3 later covers real interruption, logoff/reboot, persistent stop and no-fallback tests. No new percentage is awarded for this preparation.

G1/G2/G3/G4/G5/G6: **100/60/0/0/0/0**. This is Paytm readiness, not total MarketBrain completion or profitability.

Primary implementation references: [Task principals](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal), [task registration](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask), [task settings](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset). Local mocks cannot establish the spare's Task Scheduler rights or runtime credential access.
