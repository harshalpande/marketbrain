# Gateway-account signing check after agent evidence

**E236, 2026-11-06:** The read-only diagnostic completed successfully in **4.957 seconds**. All four source hashes match `f8a3061` with CRLF. Both service queries found ssh-agent Running, automatic startup, PID3684, expected executable and LocalSystem identity, with zero service exit codes. All six event queries completed without matching events or truncation. The protected session checkpoint hash remained unchanged.

The production worker is nevertheless stopped: its process is absent, scheduled task is Ready with last result 1, and its saved failure remains HOST_AGENT_UNAVAILABLE. Empty historical event results do not prove there was no interruption. The original ssh-add timeout/exit is unknown. This is acceptance of diagnostic capture, not gateway recovery or G3.4 acceptance.

## Why this next test is necessary

A running agent service does not establish that the dedicated Windows account can list and use its expected key. Run one temporary, non-admin, session-0 scheduled task under the existing marketbrain-gateway account. It checks exact identity and private-file absence, lists the expected single key, then signs locally twice. Native observations now retain elapsed time, timeout status, exit code, character counts and a bounded error category. Raw stdout/stderr, key comments and passwords are omitted.

This uses the existing validated temporary-task lifecycle. It does not import/delete keys, restart the agent or production supervisor, contact the VPS/broker, or create orders. It uses a fresh batch logon with the same SID: success proves current access in that logon, not the state of the former worker's logon or the cause of its earlier failure. The probe uses the custody native-command wrapper; it is not a recreation of every production-worker instruction.

The reviewed E236 receipt and preserved session checkpoint are checked before credentials or task creation. The production task must remain Ready/result1, the failed worker absent, and control LOCKED. Hashes of manifest, both controls, checkpoint and all three failure/status files are compared before/after. The temporary task is removed on success; on failure it is disabled and retained with its evidence. A changed or unknown task is not overwritten or deleted.

## Spare laptop steps

1. Open PowerShell 7 as Administrator. Keep the existing Windows login. No PuTTY, Pageant, Docker rebuild, sign-out or shutdown is needed.
2. Run the script below.
3. When prompted, type `TEST-SCHEDULED-KEY`.
4. Enter the existing **Windows marketbrain-gateway account password**, locally and hidden. This is not the administrator password, VPS password or SSH-key passphrase. Windows Task Scheduler needs it to launch the temporary task as that account; it is not written to the report or command arguments.
5. Share the one printed JSON. Allow about 1-2 minutes after entering the password. Do not rerun a failed task or reset the account/key.

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
& '.\ops\windows\TestPaytmGatewayScheduledSigning.ps1' `
    -AgentFailureReportPath 'C:\MarketBrainData\Review\paytm-agent-failure-d1938ba2c01d4a1b9759e2b81d972fed.json'
```

The earlier accepted custody report, `paytm-key-custody-20261102-112446-29cb6394513a47f687351825698006d5.json`, must remain in the same Review folder; use `-CustodyReportPath` if its original bytes were moved.

Expected: **AGENT_SIGNING_PASSED_PRODUCTION_RECOVERY_PENDING**. Share `paytm-scheduled-signing-<timestamp>-<runId>.json`. This is one report for preflight, task lifecycle, identity/signing, native observations and preservation checks. REVIEW_REQUIRED also leaves this report for analysis.

If signing passes, the next step can be reviewed production-worker recovery and an explicitly archived/replaced session baseline. If it fails, the result should distinguish missing identity, agent connection failure, timeout, unexpected identity or native error. Neither outcome authorizes silently clearing the current checkpoint. Full shutdown testing remains paused.

## Verification and progress

210 local assertions passed: 189 across 25 scheduled-task workflows, including a real Windows task-definition construction without registration, plus 21 production-state/receipt preservation assertions. Generated workers ran with identity/native boundaries substituted; no real account password, key access or task registration occurred locally. Real spare-account signing remains pending.

The original 17 task workflows still pass, including partial registration, wrong task definition, cancellation, timeout, malformed worker output and cleanup failure. New cases cover no identities, agent connection error, timeout, native error 5, successful recovery-mode capture, production-state drift and preflight receipt/checkpoint rejection before asking for credentials.

Groups **G1/G2/G3/G4/G5/G6 = 100/100/40/0/0/0%**. Accepted checkpoints remain **12/30 (40%)** of the Paytm readiness plan. This diagnostic earns no new functional milestone; real session recovery, security-negative cases, health/clock tests, login, quotes and Telegram review remain pending.
