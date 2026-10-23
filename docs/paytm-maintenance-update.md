# Reviewed VPS updates and reconnect-safe verification

**Current E173, accepted:** run `61e8afb23b9e4e73b883914330c99514` completed successfully in159.754s with target/postchecks passed and fresh administrator login owner-confirmed. Both PuTTY sessions stayed connected; no Collect or Apply retry is needed. **Do not execute the historical update handoff below again.** Use the [read-only restart review](paytm-restart-review.md). Absent reboot marker is not proof that restarts are unnecessary. Unattended gateway/broker activation remain blocked. Earlier sections retain the reviewed implementation and historical handoff, not current instructions.

**Current E172, reviewed retry r2:** run `7fb461f8bff74ee0bb15a5afed8c49bc` stopped in SIMULATE after94.305s, installation not attempted. Follow-up `146a8aba4cdf47c08e356010016eb462` passed in41.905s:70 candidates,0 holds/removals, clean package/SSH/configuration checks. Only `tzdata` candidate changed from `2026c-0+deb13u1` to `2026e-0+deb13u1`; installed version remains `2026b-0+deb13u1`. The changed candidate explains rejection of the fixed manifest, though the original simulation output was not retained. Owner authorized a reviewed retry. All69 other entries remain unchanged. The instructions below are updated; do not use the earlier Apply command without the two additional evidence paths.

2026-10-23 E170/E171. The owner backup run `897a81468f7d4ac0ba034fc15797b6fa` passed in **95.89 seconds**: 19,281,920-byte archive (18.39 MiB), source comparison passed, package state unchanged. Independent HosterDaddy browser/VNC login was owner-confirmed. Do not rerun the backup or earlier accepted route/clock/preflight batches.

## Purpose, authority and recovery limits

The next run is **real VPS maintenance, not a read-only test**. Its purpose is to install the exact 70 previously reviewed Debian package versions and verify package health, unchanged gateway configuration, stopped proxy, SSH syntax and VPS time synchronization. Fresh administrator login is then owner-tested. Success leaves restart review pending; it does not activate the gateway, authenticate Paytm, certify quotes or enable orders.

The backup remains on this VPS. It preserves selected configuration/package metadata and administrator SSH files; it is **not an off-host copy, tested restore, full-system image or package rollback**. Loss of the VPS/disk is not covered. The runner explicitly requires owner acceptance of that limitation before copying an update command. Keep the independently tested browser/VNC console available. No provider rescue/snapshot capability is assumed. If this recovery limit is unacceptable, decline the confirmation and arrange off-host recovery first.

Package scripts can restart affected services. Configuration preservation is requested through dpkg `--force-confdef`/`--force-confold`, noninteractive frontend, UCF retention and needrestart list mode; these are not a guarantee that every maintainer script leaves every service or file untouched. There is no automatic reboot, downgrade, restore or repair. The spare application/database are not deployed or modified by this runner.

## Transaction and failure boundaries

1. Verify the exact accepted backup, failed-update and follow-up-plan JSON hashes locally. On the VPS verify the pinned host, root execution through the named administrator, root-only backup parent, gateway hashes/effective unit path/no drop-ins/no pending daemon reload, inactive proxy, no port18888 listener, valid SSH configuration, no dpkg audit errors or package holds. Require at least4 GiB available on the package-cache filesystem. This is a conservative floor, not a calculated guarantee of every package's expansion requirements.
2. Verify the original root-only staging receipt/run-id exactly matches the reviewed failed run (SIMULATE, exit1, installation not attempted) and its service is inactive/failed with MainPID0. A collected unit is accepted only with explicit not-found/inactive/dead/MainPID0 observations. Unknown, active or altered evidence blocks the retry. Create a separate root-only staging directory `/var/backups/marketbrain-maintenance/update-20261023-r2`. Existing r2 staging is refused, never overwritten or deleted. Original `/var/backups/marketbrain-maintenance/update-20261023` remains untouched, including logs, worker and receipt. Launch a separate systemd service with no restart policy. Private logs and the worker remain in r2. Administrative credentials are not stored there by this script.
3. Recheck backup hash and archive/source comparison, installed versions, refresh APT indexes with errors fatal, and compare both the full upgrade simulation and the pinned installation simulation to the committed 70-row manifest. Changed/missing/extra versions, additions or removals stop the operation. A newer repository version can therefore legitimately require review rather than silently broaden authorization.
4. Download only the pinned upgrades. Before dpkg installation an APT archive hook checks all 70 archive package/version identities and the installed baseline. Installation uses no-download/only-upgrade/no-remove/no-recommends. Signed repository validation remains APT's responsibility; no insecure or unauthenticated override is supplied.
5. Verify exact installed target versions, package/SSH/configuration/stopped-state conditions and `NTPSynchronized=yes`. Record whether `/var/run/reboot-required` exists. Absence is **not** proof that no service/kernel restart is needed or that all security patches are current. Fresh administrator key-login/sudo is separately owner-confirmed.

Downloads and observation are bounded; **installation itself is not forcibly timed out**, because terminating dpkg can damage package state. PuTTY observation prints the current phase every5 seconds for up to20 minutes. A dropped SSH session or expired observation does not authorize a second installation: collect the same job. systemd detachment is designed for SSH loss, not power-loss/reboot recovery; no automatic replay after a reboot.

The private worker records a small atomic receipt with phase, exit code, installation-attempted flag, postcheck flag, safe failure category and reboot marker. Simulation command failures now have separate UPGRADE_SIMULATION_FAILED/EXACT_SIMULATION_FAILED categories; a successful but different plan retains UPGRADE_PLAN_CHANGED/EXACT_PLAN_CHANGED. Simulation stdout is retained in root-only stage files, not shared wholesale. Unknown/missing receipts stay UNKNOWN; failed installations stay POSSIBLE_PARTIAL_CHANGES_REVIEW_REQUIRED. There is no automatic fix-broken, dpkg repair, rollback, service kill or retry. Share the sanitized JSON, never the private archive or raw log. A launch failure can be ambiguous: do not delete the staging directory to bypass its guard.

[APT's Debian manual](https://manpages.debian.org/trixie/apt/apt-get.8.en.html) documents simulations, pinned versions and download/upgrade restrictions. The [APT configuration manual](https://manpages.debian.org/trixie/apt/apt.conf.5.en.html) documents pre-install archive lists and aborting when a hook fails. [systemd-run's Debian manual](https://manpages.debian.org/trixie/systemd/systemd-run.1.en.html) documents transient services independent of the invoking SSH process. These mechanisms do not guarantee an uninterrupted upgrade; real VPS acceptance remains pending.

## Historical update handoff - already completed; do not rerun

1. Keep all other VPS package/configuration jobs idle. Keep VNC recovery available and the existing verified administrator PuTTY window open. No gateway Pageant key, START-TEST, STOP or SERVER_READY is used here.
2. In administrator PuTTY run `sudo -v`, entering the sudo password there only.
3. In ordinary PowerShell7 on the spare laptop run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
$backup = 'C:\MarketBrainData\Review\paytm-maintenance-backup-20261023-095415-897a81468f7d4ac0ba034fc15797b6fa.json'
$plan = 'C:\MarketBrainData\Review\paytm-maintenance-plan-20261023-104652-146a8aba4cdf47c08e356010016eb462.json'
$failedRun = 'C:\MarketBrainData\Review\paytm-maintenance-update-20261023-102211-7bef6029f25a4a5fb474ef5ead505a8f.json'
foreach ($file in @($backup, $plan, $failedRun)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required evidence missing: $file" }
}
& '.\ops\windows\UpdatePaytmMaintenance.ps1' -BackupEvidencePath $backup -PlanEvidencePath $plan -FailureEvidencePath $failedRun
```

4. In PowerShell, read the real-change/recovery warning and type `UPDATE-REVIEWED-PACKAGES` only to authorize that scope. When asked to prepare PuTTY, run `sudo -v` again if needed; return to PowerShell and press Enter. The command is now on the clipboard. Record the **VPS job ID** printed by PowerShell.
5. Paste the command into PuTTY once. It needs no further typed confirmation in PuTTY. Wait for phase messages and the final receipt. Do not Ctrl+C an installer or manually reboot. No Docker build is needed.
6. Copy only `BEGIN_PAYTM_UPDATE_<id>` through `END_PAYTM_UPDATE_<id>`, including both lines, into the Windows clipboard. Return to PowerShell and press Enter within40 minutes. Do not copy private logs or extra terminal lines.
7. If postchecks pass, open a **new** PuTTY connection using the existing administrator key and verified host fingerprint. Run `whoami` then `sudo whoami`; expect `marketbrain-admin` then `root`. Keep the old window open. In PowerShell type `FRESH-LOGIN-OK` only after both succeed, otherwise `NOT-VERIFIED`.
8. Share the one `paytm-maintenance-update-...json`. Expected full status is `REVIEWED_UPDATES_VERIFIED_RESTART_REVIEW_PENDING`. A successful update is not the whole maintenance/recovery or Paytm milestone.

## If PuTTY disconnects or the observation window ends

Do **not** repeat Apply. Reconnect with the verified admin identity, run `sudo -v`, then use ordinary PowerShell7 in the repository:

```powershell
$backup = 'C:\MarketBrainData\Review\paytm-maintenance-backup-20261023-095415-897a81468f7d4ac0ba034fc15797b6fa.json'
$jobId = Read-Host 'Paste the original VPS job ID printed by the previous run (not the JSON filename suffix)'
& '.\ops\windows\UpdatePaytmMaintenance.ps1' -BackupEvidencePath $backup -Mode Collect -RunId $jobId
```

Paste its copied command into PuTTY. Collect only observes the existing job and prints its receipt; it never launches, retries or kills installation. If no receipt exists and the job never started or died, report that state for review rather than removing staging or attempting repair. Preserve the private evidence. Reboot/restart review is the next maintenance checkpoint, not an extra acceptance group.

## Local verification versus runtime acceptance

Original [E171 local evidence](evidence/paytm-maintenance-update-local-20261023.json) records46 PowerShell assertions/seven workflows and63 Bash assertions. Updated [E172 evidence](evidence/paytm-maintenance-retry-20261023.json) records retry-specific checks and the owner reports. All70 revised manifest rows are compared with the follow-up evidence. PowerShell parser/runner tests and Bash plan/archive-hook/guard/transaction fixtures use mocked system and package commands. The first owner run proves the transient worker reached SIMULATE and stopped, not that actual installation, SSH-disconnect survival or full Debian recovery works. Those require runtime acceptance. No whole-project completion percentage is inferred from assertion counts.
