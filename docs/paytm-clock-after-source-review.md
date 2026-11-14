# Three-clock comparison after E261

The source diagnostic completed, but synchronization acceptance remains open. All three read-only peer samples succeeded (+6.2752, +14.1538, +18.7051ms). System events37/35 record valid time data and synchronization. Service status still reports leap3, stratum0 and last sync error1, while peer status reports success. Do not dismiss either side as stale without evidence. The historical16.3575s phase-offset field is not a fresh independent offset measurement.

Service remains Running/Automatic; peer and permissions are unchanged. No evidence now supports replacing the time server or resetting the service. SpecialPollInterval32768s and time remaining32395s were observed; they are not proof of the cause of contradictory status. No settings are changed in this step.

## Next step and purpose

Use the existing read-only collector to compare Windows, the pinned VPS UTC clock and the actual Java account-read timestamp in five pairs. This independently checks whether the prior16-17s VPS discrepancy remains. Success is a diagnostic screen only: it does not resolve the contradictory Windows service status, prove durable automatic synchronization, authorize quote-age thresholds or close G3.5.

## Complete spare-laptop steps

1. Keep Docker Desktop and the existing MarketBrain application container running; leave jobs/tests idle. Do not rebuild or change time settings.
2. Open Pageant and load the original encrypted **marketbrain-admin administrator PPK**, not the gateway PPK. Enter the passphrase in Pageant only. No PuTTY terminal is required.
3. Open PowerShell7 as administrator and run:

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
& '.\ops\windows\TestPaytmClockSnapshot.ps1'
```

4. At the PowerShell prompt type **CLOCK-CHECK** once the admin key is loaded. Collection normally takes1-2minutes.
5. At the final prompt remove only the administrator key if added solely for this test; preserve unrelated keys and the encrypted PPK. Type **KEY-REVIEWED** in PowerShell.
6. Share the ONE printed paytm-clock-snapshot JSON, even if it reports findings.

Expected within-screen status: CLOCK_SNAPSHOT_WITHIN_SCREEN_RELEASE_PENDING. Other findings remain reviewable; no automatic repair or repeated run. No service repair, broker login or order is performed.

## Verification and progress

Unchanged collector verified locally:113 comparison/runner assertions across ten mocked workflows and28 HTTP-boundary assertions, without real SSH/Docker/HTTP access. Documentation/evidence only changed for this handoff; no application rebuild required.

Readiness remains14/30=46.7%; group percentages100/100/80/0/0/0. G3.5 clock/health acceptance stays open. A successful comparison provides independent alignment evidence; durable synchronization and application timing enforcement still require their own evidence.
