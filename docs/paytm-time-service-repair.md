# Windows Time repair after E258

**Current E259, 2026-11-15:** Repair stopped before mutation: fresh PS5.1 worker lacked the ServiceController assembly; zero repair commands, no resync, temporary task removed (11.185s). All three source hashes match cffa46a. Explicit assembly loading fixes the reproduced defect; real read-only fresh-process tests pass in PS5.1 and PS7, plus 47 helper assertions/four controller fixtures. [Retry the corrected repair](paytm-time-service-repair.md); clock alignment remains pending. Groups 100/100/80/0/0/0;14/30 (46.7%), unchanged.


The access diagnostic succeeded. Windows Time is stopped/manual, and the elevated administrator cannot obtain SERVICE_START. SYSTEM has the needed rights in the captured service descriptor. This explains the denied start; it does not yet establish a working NTP source.

## Purpose and boundaries

Run one temporary SYSTEM scheduled task on the spare laptop. It changes W32Time startup to Automatic, starts it, and requests `w32tm /resync /rediscover` against the existing configured source. It preserves the service ACL, service account, binary, NTP peer string and client settings. No credential, gateway, firewall, VPS, container or broker configuration changes are included.

The exact E258 receipt hash and current stopped/manual descriptor must match. Both parent and worker reject missing/disabled NTP client, non-NTP mode, empty peer configuration or Windows Time policy. These unobserved settings must pass preflight; this package does not guess a replacement source. Files are copied/hash-checked into an administrators/SYSTEM-only directory. The hash-checked worker uses process-only execution-policy bypass (no persistent policy change). The on-demand task has no triggers, a five-minute limit and is removed after completion. Progress uses elapsed monotonic time because synchronization can change wall time.

Microsoft documents that [resync requests synchronization and rediscover redetects network configuration/time sources](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/Windows-Time-Service-Tools-and-Settings). Command acceptance alone does not prove sustained synchronization or a five-second clock comparison result.

## Run once on the spare laptop

Use **PowerShell 7, Run as administrator**, when trading/data jobs are idle: synchronization may adjust the clock. No PuTTY, Pageant or Docker restart is required.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as administrator.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\RepairPaytmWindowsTime.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-windows-time-access-20261115-005901-8ed634625bae4a1d912cb65d17e48648.json'
```

Allow up to about four minutes for the worker plus bounded cleanup. Expected result: `TIME_SERVICE_REPAIRED_ALIGNMENT_RECHECK_PENDING`. Share the ONE `paytm-time-repair-<run>.json` printed by the script. Protected internal worker files remain under `C:\ProgramData\MarketBrainTimeRepair` for troubleshooting; they are embedded in the shareable report when available.

If synchronization fails after startup, the service may remain Running/Automatic. That partial state is intentional and reported; no automatic clock rewind, repeated repair, ACL reset or peer replacement occurs. A cleanup failure is REVIEW_REQUIRED; do not manually rerun or remove unrelated tasks. Share the report first. If the terminal is interrupted, the task has a five-minute bound but its registration may remain for reviewed cleanup.

## Verification and next gate

47 offline helper assertions cover baseline rejection, preserved configuration, exact command order, failures at configuration/start/resync/query/wait, drift and parsing. Four mocked controller workflows cover success, worker failure, report identity mismatch and task cleanup failure. These do not prove actual Windows scheduler/service operation; that is the spare-laptop test above. Native worker syntax is compatible with PowerShell 5.1; controller requires 7.

After accepting this receipt, repeat the fresh Windows/VPS/Java clock comparison, then finish remaining clock/health enforcement review. G3.5 is still open. Groups 1/2/3/4/5/6: **100/100/80/0/0/0%; 14/30 = 46.7%**. No broker login, quote or order readiness is granted by this repair.

## E259 compatibility correction

The first SYSTEM worker failed before any mutation because a clean Windows PowerShell 5.1 process had not loaded System.ServiceProcess. Mocks and syntax checks did not exercise that path. The helper now loads that assembly explicitly when needed before constructing the controller; full System namespace names are used. The regression test reproduces the original failure against cffa46a and passes with the fix, exercising the real read-only snapshot, enum and controller in fresh PS5.1 and PS7 processes. This is not proof of SYSTEM service-start or NTP success.

The receipt confirms mutationAttempted=false, commands empty, resyncRequested=false and taskRemoved=true. A retry is appropriate using the same pinned E258 diagnostic and live baseline checks. The observed existing source is time.windows.com,0x9; its availability is still unproven. No manual task cleanup or service-permission changes are needed.
