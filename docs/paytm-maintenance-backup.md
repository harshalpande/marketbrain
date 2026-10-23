# Private VPS maintenance backup

2026-10-23 E168/E169. Maintenance preflight accepted from run `f44e98badcf348a6aa7f0967236b4a9b`:76.183s, no findings, clean dpkg/SSH,70 candidates, no held packages/removals,8.04GiB free on the checked filesystem. Candidate versions match the previous capture. Do not repeat the maintenance-plan runner. Owner subsequently confirmed successful independent HosterDaddy browser/VNC login. This is owner-tested console access, not proof of provider rescue/image-restore capability.

## Purpose and exact scope

Next create one **private on-VPS configuration/package-state backup** before preparing package installation. The backup includes `/etc`, `/var/lib/dpkg`, `/var/lib/apt/extended_states` and `/home/marketbrain-admin/.ssh`. A package-selection inventory is stored alongside it. It does not access the spare laptop database, market datasets, application container or broker.

`/etc` and administrator SSH files can contain sensitive material, including host private keys and password hashes. The unencrypted archive stays inside a new root-owned0700 directory under `/var/backups/marketbrain-maintenance/<run-id>`, with0600 archive permissions. It is not copied to Windows or uploaded. **Share only the generated JSON, never configuration.tar, package-selections.txt or private.log.** Existing paths/permissions are not overwritten or repaired; duplicate run directory, symlinked/unexpected parent, host/config drift, active proxy/listener, unhealthy package state or insufficient space stop the run. Parent locations must resolve exactly, be root-owned and not group/world writable.

The launcher pins the exact accepted maintenance JSON hash. It asks for owner confirmation of independently tested console login and explicit backup authorization before copying any VPS command. No passwords/private keys appear in the payload. Admin key use remains interactive; no new unattended credential custody.

The VPS rechecks existing host/configuration/stopped-state/SSH/package-health conditions, validates source paths, measures apparent source size (cap512MiB), and requires free space of at least twice that measurement plus512MiB on the destination filesystem. It creates a unique directory without replacing existing backups, captures package selections, creates a GNU tar archive with ACL/xattr/numeric ownership metadata, compares archive members to the source, checks the dpkg status hash unchanged, and reports archive bytes/SHA256. No extraction, restore, update, download, index refresh, service change or reboot. TAR_OPTIONS is cleared; source symlinks are not dereferenced. Live configuration changes can make comparison fail; keep jobs idle.

[Debian backup/recovery guidance](https://www.debian.org/releases/trixie/release-notes/upgrading.en.html) motivates configuration/package-state preservation and independent access. [GNU tar's Debian manual](https://manpages.debian.org/trixie/tar/tar.1.en.html) documents archive comparison and metadata options. This is not a Debian major-version upgrade.

## Limits and failure handling

- Archive comparison is not a restore rehearsal, atomic filesystem snapshot, full-system image or package downgrade mechanism. An on-VPS backup does not protect against disk/VPS loss. Off-host recovery/rescue strategy still needs review before updates; no provider snapshot capability is assumed.
- It does not prove preservation of targets outside the selected scope reached by symlinks, or every type of ACL/xattr restoration. GNU tar comparison is used without overstating metadata restore proof.
- Source writes are not frozen by a filesystem snapshot or dpkg transaction lock. Owner keeps configuration/package activity idle; source compare and status hash detect observed drift, not all possible concurrent races.
- Partial files are retained privately on failure, never automatically deleted or retried. The report identifies failure phase; private raw logs remain on the VPS. Do not post those logs without a separately redacted review.
- Missing/malformed receipt leaves backup state UNKNOWN, not NOT_CREATED. If interrupted, do not assume a backup succeeded or blindly rerun. Outer command limit600s plus10s termination grace; archive creation and comparison each180s plus5s. An abrupt SSH/kill interruption may prevent the final receipt, but does not authorize updates.
- This package has no install/upgrade or restart command. Passing does not activate unattended operation, approve broker quotes or enable orders.

## Spare-laptop handoff

1. Keep package/configuration jobs idle. Keep the independently tested HosterDaddy console available. Use ordinary PowerShell7 and a verified `marketbrain-admin` PuTTY session.
2. In PuTTY run `sudo -v`; type your sudo password there only.
3. In PowerShell7:

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
$evidence = 'C:\MarketBrainData\Review\paytm-maintenance-plan-20261023-093443-f44e98badcf348a6aa7f0967236b4a9b.json'
if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) { throw 'Accepted maintenance report missing; locate the original file.' }
& '.\ops\windows\BackupPaytmMaintenance.ps1' -MaintenanceEvidencePath $evidence
```

4. In PowerShell enter `CONSOLE-LOGIN-OK` to record your independently tested console login, then `CREATE-PRIVATE-BACKUP` after reading the scope and completing PuTTY sudo. It copies the command.
5. Paste into PuTTY; it runs without interactive input. No START-TEST/STOP/SERVER_READY, no gateway key or tunnel. Keep PuTTY open, allow the stated bounds. Progress appears between phases; tar output is private.
6. Copy only the complete `BEGIN_PAYTM_BACKUP_<id>` through `END_PAYTM_BACKUP_<id>` block, including both lines. Return to PowerShell and press Enter within20minutes. Exclude progress/private-path text outside the block.
7. Share the ONE `paytm-maintenance-backup-...json`. Expected status: `PRIVATE_BACKUP_COMPARED_UPDATE_AND_RECOVERY_REVIEW_PENDING`. If no complete block appears, finish the PowerShell capture with the visible error copied; share the sanitized JSON and non-secret error, not the private archive/log.

No rebuild is needed. After review, prepare the controlled update transaction and post-update checks, with recovery limitations and restart effects explicitly reviewed. This remains batch1 of the six published acceptance groups, not a new seventh batch.

## Verification

E169 local:49 PowerShell assertions including six mocked launcher workflows,28 Bash assertions including a native GNU tar archive/compare fixture on disposable local files and mocked pre-write guards. The file-size-limit primitive is mocked because Windows Git Bash cannot enforce Linux RLIMIT_FSIZE; production requires it to succeed before writing. Actual root-owned Debian permissions, resource-limit enforcement, full production backup and runtime recovery remain unverified until owner execution. Local GNU tar on Windows does not certify Debian ACL/xattr restoration. Existing49-assertion maintenance reader regression retained.
