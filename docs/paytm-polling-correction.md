# Controlled Windows Time polling correction after E263

E263 confirms three unsynchronized service-status observations, despite nine small peer offsets and preserved Running/Automatic service. User authorized the proposed correction. The current clock is close to the peer; this targets service synchronization health, not a manual clock setting.

Microsoft documents switching the peer flag from0x9 to0x8 to use automatic polling within existing MinPollInterval/MaxPollInterval rather than SpecialPollInterval: [official workaround](https://learn.microsoft.com/en-us/troubleshoot/windows-server/identity/w32time-sync-specialpollinterval-ignored). This is an evidence-supported remediation candidate, not a proven diagnosis or promised cure. Existing Min/Max intervals remain unchanged; polling is not guaranteed to occur every few seconds.

## Exactly what changes

The existing reviewed SYSTEM-task launcher now has an explicit AdaptivePolling mode. It requires the exact E263 report hash and live Running/Automatic service, original service ACL, NTP mode, enabled client, no Windows Time policy and exact time.windows.com,0x9 peer. Both parent and worker check the baseline.

Before mutation, the SYSTEM worker saves its before-image in the protected per-run worker.json. It executes only:

- `w32tm /config /manualpeerlist:time.windows.com,0x8 /update`
- one `w32tm /resync /rediscover`
- three status/source observations separated by10-second waits.

No service stop/start, replacement server, service ACL, firewall, broker or application changes. Resync can adjust wall time; run while application jobs are idle. Native exit0 alone is insufficient: explicit command success and all three recognized synchronized status results are required. Source remains time.windows.com; service remains Running/Automatic.

On caught failure, rollback first confirms the exact expected configuration apart from the owned peer-flag change. It restores0x9 with `/config /update`, verifies the restored value and leaves a REVIEW_REQUIRED report. Drift blocks automatic overwrite. Rollback is attempted only after mutation; failed rollback is separately reported. Clock movement caused by resync cannot be rolled back. Forced termination/power loss can prevent rollback; the protected before-image remains, and no automatic retry should be attempted. Parent waits at most7minutes; task has an8-minute ceiling and owned-task cleanup follows. Normal run should take roughly40-90seconds.

## Run on spare laptop

PowerShell7 **as administrator**, with jobs idle. No PuTTY, Pageant, rebuild or reboot.

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
  -Mode AdaptivePolling `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-clock-health-6ee77eb88e18431ebe55db990ef76ce5.json'
```

Expected: TIME_POLLING_CHANGED_SYNC_OBSERVED_RELEASE_PENDING. Share the ONE paytm-time-repair JSON regardless of outcome. Protected worker data and before-image remain on the laptop. If REVIEW_REQUIRED, do not repeat the original startup repair or edit permissions; share the report, including its rollback fields.

## Verification and next gate

22 polling assertions across eight mocked workflows: success, partial configuration failure, zero-exit resync failure, unhealthy status, query timeout, rollback failure, unrelated drift and changed baseline. Four controller workflows pass in each mode (eight total). Existing47 helper assertions and8 semantic regressions pass; fresh Windows PowerShell5.1 read-only snapshot/assembly smoke test passes. No real local service mutation was used for testing.

A pass establishes bounded post-change service status, not multi-hour stability or trading readiness. G3.5 clock-health policy/application timing enforcement still needs acceptance. Groups100/100/80/0/0/0;14/30=46.7%, unchanged until checkpoint evidence is complete.
