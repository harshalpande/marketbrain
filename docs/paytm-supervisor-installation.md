# Locked Windows supervisor installation

**Current E206, 2026-11-02: run the recovery below, not the original installer.** The submitted installation registered the startup task but exited1 before a heartbeat (26.842s); cleanup recorded no failure. All11 source hashes match8a87ae5 CRLF. Account/custody/batch policy prerequisites passed. No broker contact or orders occurred.

The runner mistakenly imported `host.ps1` as a script file. This fails under Restricted execution policy, unlike the inline-loading mechanism already used by the accepted signing worker. Local child-process tests reproduce the defect and pass with the corrected loading path. The original report omitted bootstrap errors and execution-policy values, so its exact remote exception is not proven. [Microsoft documents](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1) Restricted as the Windows-client default when no scope supplies a policy; a different user's setting does not establish the gateway account's policy.

The corrected runner verifies source hashes before inline evaluation, records startup stages and safe exception metadata even before the helper/native library is usable, and includes observed policy scopes in successful worker evidence. It does not change policy. Explicit managed MachinePolicy/UserPolicy settings stop for review rather than being bypassed. Bootstrap errors before identity verification or before acquiring the exclusive work lease cannot be written by the worker; task exit remains available for those cases.

Recovery validates the exact supplied failure receipt, existing disabled/stopped task, root/work permissions, source/manifest hashes, STOP control and no unexpected worker evidence. It holds controller and worker locks, preserves original runner/manifest in a protected backup, replaces only the runner and its manifest hash, then reuses the stored task credential for heartbeat/duplicate/STOP/restart verification. It does not reset passwords, register a new task, import keys or rebuild the DLL. A failure retains STOP and disables the matched task; backups and diagnostics remain. No blind repeated recovery or automatic rollback of an unreviewed state.

Local validation:25 bootstrap assertions across8 actual PowerShell5.1 child-process cases,19 recovery guards with actual file backup/replacement,48 host regressions and79 gateway regressions. Child fixtures substitute local identity/session checks; task/ACL operations are mocked in recovery tests. These are not spare-account acceptance. [Evidence](evidence/paytm-supervisor-startup-recovery-local-20261102.json).

Run this once in **PowerShell7 as Administrator** on the spare laptop. No PuTTY, password entry, Pageant changes, Docker rebuild or VPS action is needed:

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 as Administrator.' }
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
& '.\ops\windows\RepairPaytmGatewaySupervisor.ps1'
```

Expected result: `LOCKED_SUPERVISOR_RECOVERY_PASSED_TRANSPORT_PENDING`. Share the single printed `paytm-supervisor-recovery-*.json`. G1/G2/G3/G4/G5/G6 remain **100/60/0/0/0/0** until further runtime acceptance.

## Original installation design and handoff (historical for this machine)

E205, 2026-11-02. E204 background signing is accepted. This batch installs the persistent Windows supervisor **host**, its startup task, process containment and monitoring. It deliberately has no transport-enable operation. Production SSH observation/reconnection adapters and managed VPS lifecycle remain to be integrated; this installation alone does not close G2.4 or enable Paytm login.

## What one run does

1. Checks the exact accepted E198 custody and E204 signing receipts, existing account/SID, protected custody files, running agent, Users-only membership and current batch-logon allow/deny policy. Reads policy only; no account recreation, password reset or key import.
2. Constructs and checks the actual Windows Task Scheduler definition before installation. Prompts once for the **existing Windows password for marketbrain-gateway**, not the encrypted SSH key passphrase. Task Scheduler stores its registration credential; the registration API receives a transient managed string. No credential is written to scripts, command arguments or evidence. Memory erasure is not claimed.
3. Creates administrator-owned `C:\ProgramData\MarketBrainPaytmGateway\supervisor-v1` with gateway read/execute access, and a separate gateway-writable `supervisor-work-v1` directory. Compiles the small process-containment helper with native Windows PowerShell 5.1. The runner also uses native 5.1, independent of a per-user PowerShell 7 installation. A manifest binds the installed sources and DLL hashes.
4. Registers `MarketBrain-Gateway-Supervisor-v1` initially disabled: Password logon, Limited privileges, exact existing SID, startup trigger delayed 30 seconds, IgnoreNew instances, no wake/network/battery requirement, no automatic failure restart, and explicit unlimited execution duration. Then enables and demand-starts it. The host requires Session 0, acquires an exclusive file lease, joins a kill-on-close Windows Job Object before starting children, and verifies existing agent identity and one signature at startup.
5. Observes advancing heartbeats; requests a duplicate start and verifies the same instance continues; writes persistent STOP and checks exit 0; starts again while STOP remains and verifies no signing/activation; explicitly returns to LOCKED and verifies a new running instance and advancing heartbeats. All observations are embedded in one shareable JSON.

Successful final state: startup task enabled, host running **LOCKED**, existing keys/accounts retained. Its heartbeat is a statement about the locked host, not a continuously retested signing credential, network health, broker login or quote freshness. All transport/broker/order flags stay false. The runner has no SSH connection path in this release. The existing gateway state machine remains independently tested but is not yet wired to production transport observations.

The next installation step will integrate transport observations/reconnection and the VPS managed service with the established host. Then actual interruption, logoff/reboot and no-fallback cases are accepted in G3. A configured startup trigger is not evidence of a cold boot.

## Failure and shutdown behavior

- Controller waits use monotonic deadlines (60 seconds per observation); status requires installation/instance binding and sequence advancement, so a stale file cannot pass as a live heartbeat. UTC is informational only.
- Startup signing commands have 10-second deadlines and capped stdout/stderr tails of 16 KiB each. Arbitrary native text is not copied into the shared report. A process Job Object contains descendants; closing the owner process kills its job's children. This follows the [Windows Job Object lifetime contract](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) and was tested locally with real harmless child processes.
- Heartbeats replace one bounded file atomically. Readers allow delete-sharing so concurrent replacement does not intermittently fail. A worker failure after initialization records a persistent block marker; there is no automatic rearm.
- On installer failure, it writes STOP and disables/stops only the task whose ownership and definition still match this installation. Files and evidence remain for diagnosis. An unrelated/changed task is not overwritten. Do not delete the account or blindly repeat installation; an existing installation is deliberately refused.
- To disable the accepted host later, run `& '.\ops\windows\StopPaytmGatewaySupervisor.ps1'` from elevated PowerShell 7 in the repository. It validates ownership, retains STOP, disables/stops the task and checks its terminal state. It preserves account, agent key and files. This release provides no unattended transport activation command.

## Run once on the spare laptop

No PuTTY, Pageant manipulation, VPS proxy start, Docker rebuild, application restart or new key export is needed. Keep the accepted JSON reports at their original `C:\MarketBrainData\Review` paths. Use **PowerShell 7 as Administrator**:

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 as Administrator.' }
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
& '.\ops\windows\InstallPaytmGatewaySupervisor.ps1'
```

When prompted, enter the existing gateway **Windows account password locally**. The remaining checks normally take about a minute; deadlines are bounded and a failure stops the batch. Share only the printed `paytm-supervisor-install-*.json` file. Expected success: `LOCKED_SUPERVISOR_INSTALLED_TRANSPORT_PENDING`.

## Evidence and completion

Local verification: 48 new assertions, including real native C# compilation, bounded process output/timeouts, quoting, owner-death descendant cleanup, unrelated-process preservation, exclusive lease, atomic JSON, host loop STOP/block behavior, native task constructors and mocked controller lifecycle. Existing 79 supervisor state-machine/argument/process checks also pass. These tests register no actual task, change no local account/policy and contact no broker/VPS. [Evidence](evidence/paytm-supervisor-host-local-20261102.json).

Accepted group percentages remain **G1 100%, G2 60%, G3–G6 0%**. No runtime completion is credited until the spare report is reviewed; a successful locked-host report will be recorded as a G2.4 prerequisite, not a completed production-tunnel checkpoint.
