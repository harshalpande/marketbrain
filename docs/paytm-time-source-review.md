# Read-only time-source review after E260

E260 establishes service-start repair only. Windows Time is Running/Automatic, the service ACL and time.windows.com,0x9 peer are unchanged, and the temporary task was removed. The resync output explicitly says no time data was available despite exit0. Status reports leap3 (not synchronized), stratum0 and last error1. A last-success timestamp and phase offset do not override those failure indicators. The old success label is not accepted as synchronization evidence.

The repair checker now requires positive resync text and recognized healthy English status fields; unknown/localized output remains review-required. Eight semantic regressions include this exact zero-exit failure, alongside47 helper assertions, four repair-controller and four collector workflows. No service repair retry is needed.

## Next collection

The new collector pins E260, checks Running/Automatic and the unchanged peer, captures configuration/peers/status/source, requests three read-only stripchart samples from the existing server, captures status/source again and the latest20 System Time-Service events. Native requests have20-second deadlines and partial results are saved after each. Events are bounded by count rather than a clock-dependent date window. No resync, NTP configuration, ACL, task, firewall or clock-setting commands are issued. Existing Windows Time may synchronize independently during observation.

Microsoft describes [no-time-data troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/error-message-run-w32tm-resync-no-time-data-available) and [Windows Time commands](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/Windows-Time-Service-Tools-and-Settings). A stripchart response alone does not prove the service's NTP path or clock alignment: stripchart and the service use different source-port behavior. We have not established DNS, firewall or provider failure. No peer replacement is authorized by this evidence.

## Spare laptop

Use PowerShell7 as administrator for event access. No PuTTY/Pageant or Docker changes are needed. Do not manually change the clock during collection.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\ReviewPaytmTimeSource.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-time-repair-75e26f6dd41842c1bfbfb1a9c1d96216.json'
```

Share the ONE paytm-time-source JSON. Normal collection should be under a minute; timeouts can extend it. TIME_SOURCE_REPORTS_SYNC_ALIGNMENT_PENDING indicates recognized service status, not verified clock accuracy. TIME_SOURCE_CAPTURED_SYNC_UNCONFIRMED or TIME_SOURCE_PARTIAL_REVIEW_REQUIRED requires report review, not repeated repair. Event text may include local computer/server names; no credentials are collected.

Once service status supports synchronization, use the three-clock comparison before remaining G3.5 acceptance. Readiness remains14/30=46.7%; groups100/100/80/0/0/0. Broker login, quotes and orders remain pending.
