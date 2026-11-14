# Bounded Windows clock-health observation after E262

**Current E264, 2026-11-15:** Adaptive polling correction accepted in42.829s. Explicit config/resync success; three samples leap0/stratum5/error0, phase estimate26.328ms. Same time.windows.com server, flag0x9->0x8; Running/Automatic and ACL preserved, task removed, no rollback. Three source hashes matchf1618ec. [Next: isolated Java timing-guard verification](paytm-java-timing-guard.md);39 deterministic checks and full collector pass locally, production wiring pending. G3.5 open;14/30 (46.7%), groups100/100/80/0/0/0.


**Historical E263, 2026-11-15:** Health capture completed in75.187s; all nine peer offsets -10.468..+35.689ms, service Running/Automatic and configuration preserved. All three service observations remain unsynchronized; no health acceptance. Three source hashes match6b896f1. Owner authorized [controlled polling correction with rollback](paytm-polling-correction.md): same server,0x9 to0x8, one SYSTEM task, resync and three status samples. Local tests only; runtime pending. Groups100/100/80/0/0/0;14/30 (46.7%), unchanged.


E262 passed the independent three-clock screen: all10 observations usable, VPS NTP yes5/5, no findings. Conservative VPS-minus-Windows bounds are -0.043..+0.964s; Java-minus-Windows -0.086..+0.073s; Java-minus-VPS -1.050..+0.116s. These intervals include measurement uncertainty; they are not exact clock offsets. The previous16-17s difference is absent in this observation. Container unchanged, key cleanup confirmed, six source hashes verified.

## Why one further clock batch

E261 had peer samples within19ms and synchronization events, but current Windows service status still reported leap3/stratum0/error1. E262 proves current relative alignment, not ongoing synchronization. This batch samples current Windows status/source/peers and three read-only peer offsets in each of three rounds, separated by30seconds. It captures the contradiction if still present instead of granting approval from one successful command.

There are no resync, clock-setting, peer, ACL, task, firewall, gateway or application changes. No PuTTY/Pageant/Docker interaction. Existing Windows Time can adjust the clock independently. A sixty-second observation cannot prove multi-hour drift, reboot persistence or durable automatic synchronization, particularly with the observed32768-second special poll interval. No service restart or poll-interval change is made to force a pass.

## Spare-laptop handoff

Open PowerShell7; administrator mode is acceptable. Keep time settings unchanged. Normally about75seconds; command timeouts can extend the run. A JSON checkpoint is written after each round, including partial native failures.

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
& '.\ops\windows\ReviewPaytmClockHealth.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-clock-snapshot-20261115-012410-af351b5a10e64d6b8b72a14d5598667b.json'
```

Share the ONE paytm-clock-health JSON printed at completion. CLOCK_HEALTH_OBSERVATION_PASSED_POLICY_PENDING means all three status observations were recognized healthy, all nine offsets were inside the existing five-second diagnostic screen, and configuration remained unchanged. It does not approve trading timing or durable sync. CLOCK_HEALTH_CAPTURED_WITH_FINDINGS preserves missing/unrecognized/unsynchronized results; do not rerun repairs to suppress findings.

## Verification and remaining boundary

23 offline assertions across seven mocked batches cover healthy, unsynchronized, unrecognized, timed-out, incomplete peer data, excess offset and insufficient-duration cases. Source hashes and prior receipt pin are included in the real collector. Runtime remains to be verified by the owner.

G3.5 records E262 as a prerequisite, not completion. Readiness14/30=46.7%; groups100/100/80/0/0/0. After this observation, review Windows health findings and the remaining application clock/health timing policy and fail-closed enforcement before accepting G3.5. Login/quotes/Telegram review remain subsequent groups.
