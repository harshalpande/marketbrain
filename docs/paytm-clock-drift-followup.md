# Clock findings: inspect current Windows synchronization before repair

**Current E259, 2026-11-15:** Repair stopped before mutation: fresh PS5.1 worker lacked the ServiceController assembly; zero repair commands, no resync, temporary task removed (11.185s). All three source hashes match cffa46a. Explicit assembly loading fixes the reproduced defect; real read-only fresh-process tests pass in PS5.1 and PS7, plus 47 helper assertions/four controller fixtures. [Retry the corrected repair](paytm-time-service-repair.md); clock alignment remains pending. Groups 100/100/80/0/0/0;14/30 (46.7%), unchanged.


**Historical E258, 2026-11-15:** Windows Time access diagnosis captured in 7.911s: stopped/manual service; elevated administrator lacks SERVICE_START, SYSTEM has the required rights. Six source hashes match 2592b23. [Next: one-time SYSTEM repair preserving service ACL and existing time peers](paytm-time-service-repair.md). Offline verification: 47 assertions and four controller workflows; actual repair and fresh clock comparison pending. G3.5 remains blocked; groups 100/100/80/0/0/0, 14/30 (46.7%), unchanged.


E257, November15,2026. Report7c7ca6cd6cf041d0a795d1ed662fd109 ran52.798s, status CLOCK_SNAPSHOT_CAPTURED_WITH_FINDINGS. Collection itself succeeded. Conservative VPS-minus-Windows bounds are16.1884604 to17.3248532 seconds; Java-minus-Windows is -0.0298182 to0.0328845 seconds. Java-minus-VPS is -17.3546714 to-16.1555759 seconds. All five VPS samples reported NTPSynchronized=yes. This does not independently prove absolute VPS UTC accuracy.

The earlier Windows Time diagnostic found SERVICE_START access denied even with administrator elevation; Windows time was manually corrected afterward. That old evidence is not proof of current permissions or current sync configuration. Repeating a resync command or broad service ACL reset is not justified yet. Do not change clocks during collection.

## Next command

No Pageant/PuTTY, Docker requirement, gateway restart or rebuild. Open PowerShell7 as Administrator in the spare repository after pulling main:

```powershell
$evidence = 'C:\MarketBrainData\Review\paytm-clock-snapshot-20261115-005346-7c7ca6cd6cf041d0a795d1ed662fd109.json'
& '.\ops\windows\ReviewPaytmWindowsTimeAccess.ps1' -OperationsEvidencePath $evidence
```

The parameter name OperationsEvidencePath is retained for compatibility; the collector now accepts the exact reviewed new clock report hash as well as the original historical evidence. It does not require the old October report.

Seven bounded read-only queries capture status/configuration/service security/triggers/time policy; a child opens and closes service handles to determine effective rights. No service start, resync, registry/ACL edit, credential use or external request is performed. Normally under1 minute; pathological queries may take several minutes with progress. Expected TIME_ACCESS_CAPTURED_REPAIR_REVIEW_PENDING or partial-review status. Share the single printed paytm-windows-time-access JSON. Success means diagnosis captured, not clock repaired.

## Verification and progress

71 diagnostic assertions/nine mocked workflows passed. The local portable PS7 compiler reported CS8021, so native compilation was verified separately under Windows PowerShell without invoking service operations. The freshly uploaded report was checked against the new pinned hash. Six source hashes are now included in the diagnostic output.

G3.2 remains accepted, G3=80%, bounded Paytm plan14/30 (46.7%). G3.5 is blocked on clock/health acceptance. The next repair will be based on the current service/permission/policy result; the five-second screening threshold is unchanged and is not a trading tolerance.
