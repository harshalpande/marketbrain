# Reviewed scanner installation and immediate restart scan

## Accepted plan and scope

E177 accepts owner plan `6b823ad4ebfe4de8b310e4897d7df4d9`: **51.727 seconds**, simulation exit0, six new packages and matching configuration actions, no upgrades/removals or plan findings. Current health and all70 previously installed targets passed. The absent scanner still prevents restart assessment. This next operation installs the scanner and runs the read-only scan in the **same job**, not a replay of the completed maintenance upgrade.

| New package | Pinned version |
| --- | --- |
| libintl-perl | 1.35-1 |
| libmodule-find-perl | 0.17-1 |
| libproc-processtable-perl | 0.636-1+b3 |
| libsort-naturally-perl | 1.03-4 |
| libterm-readkey-perl | 2.38-2+b4 |
| needrestart | 3.11-1 |

This is a **real VPS change** with explicit `INSTALL-SCANNER` confirmation. Keep other package/configuration jobs idle and the independently tested browser/VNC console available. The runner creates a fresh private same-VPS backup of `/etc`, dpkg metadata and APT extended states, compares it before proceeding and guards the dpkg status hash before installation. This is not an off-host backup, tested restore, full-system image or package rollback. Old update/backup evidence stays untouched; do not upload any private archive/log.

## Transaction safeguards and limits

- Existing pinned host/SSH/gateway/70-target guards must pass; six packages and `/etc/needrestart` must not already be installed/present. Fixed non-overwriting stage: `/var/backups/marketbrain-maintenance/scanner-install-20261023`. An existing stage stops Apply rather than assuming it is safe to retry.
- Refresh signed APT indexes, then compare both candidate and exact-version simulation actions to the six-package manifest. New dependencies, changed versions, upgrades, removals or configuration actions stop before installation. Sources with per-source trust/expiry overrides require review; default source paths and authentication/HTTPS/expiry checks are explicit.
- Use a new private download cache; preview all six archive URIs, allow only Debian archive/security pool hosts and cap their combined declared download size at50MiB. APT performs its package authentication checks. A pre-install hook verifies the exact six package/version/architecture archive identities and unchanged installed state. This is a scoped host/package check, not a full repository/key trust audit.
- Suppress the `needrestart` APT hook during installation (`NEEDRESTART_SUSPEND=1`, list-only mode). Add the new root-owned `/etc/needrestart/conf.d/99-marketbrain-list-only.conf` without overwriting an existing file; it sets the default restart mode to list-only. Explicit later administrator overrides remain possible. [Debian's needrestart manual](https://manpages.debian.org/trixie/needrestart/needrestart.1.en.html) documents the hook-suppression variable and non-restarting batch/list modes.
- Verify all six versions/architectures, unchanged70 targets, clean package/SSH/gateway/time state, then immediately collect the existing bounded `needrestart -b -r l` screen. No requested service restart, reboot, gateway activation or broker action is included. Package maintainer scripts still run as part of installation; this is not equivalent to a read-only diagnostic.
- A detached systemd job records a private log and atomic non-secret receipt. Do not kill dpkg on a timer. Bounded observation ends after20minutes without killing the worker; Collect only reads the same run. SSH-loss survival is designed and locally mocked, not yet proven on this VPS. No automatic repair, retry, rollback or post-reboot replay.

[APT's manual](https://manpages.debian.org/trixie/apt/apt-get.8.en.html) documents exact versions, simulations, download-only and no-download modes. Its [configuration reference](https://manpages.debian.org/trixie/apt/apt.conf.5.en.html) documents pre-install archive hooks. These controls do not remove all installation risk or guarantee that no restart need will be found.

## Complete spare-laptop handoff

Keep a verified `marketbrain-admin` PuTTY session open and VNC recovery available. In ordinary **PowerShell7 on the spare laptop** run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 first.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Stop: repository is not clean or Git failed.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Stop: expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Pull failed. Do not continue.' }
$plan = 'C:\MarketBrainData\Review\paytm-scanner-plan-20261023-160927-6b823ad4ebfe4de8b310e4897d7df4d9.json'
if (-not (Test-Path -LiteralPath $plan -PathType Leaf)) { throw 'Accepted scanner plan not found.' }
& '.\ops\windows\InstallPaytmRestartScanner.ps1' -PlanEvidencePath $plan -Mode Apply
```

1. **PowerShell:** read the scope/recovery warning. Type `INSTALL-SCANNER` only if accepted.
2. At its next prompt, switch to **PuTTY**, run `sudo -v` and enter the password there. Return to **PowerShell**, press Enter; the VPS command is copied automatically.
3. **PuTTY:** paste once. No START-TEST/STOP input. Phase progress appears every5seconds. Keep it running; installation itself has no forced timeout.
4. Copy the entire `BEGIN_PAYTM_SCANNER_INSTALL_<job-id>` through `END_PAYTM_SCANNER_INSTALL_<job-id>` block, including both boundaries. Do not include prompts or private log output.
5. Return to **PowerShell**, press Enter within40minutes, and share the one `paytm-scanner-install-...json` printed. No Docker rebuild, Pageant gateway key or broker credentials are needed.

## Only if observation is interrupted

Do **not** run Apply again, delete staging, stop the service or interrupt dpkg. Preserve the printed **VPS job ID** (not the output filename suffix). In a new PowerShell7 window use the same repository and input plan, then:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$plan = 'C:\MarketBrainData\Review\paytm-scanner-plan-20261023-160927-6b823ad4ebfe4de8b310e4897d7df4d9.json'
$job = Read-Host 'Paste the VPS job ID printed by the interrupted run'
if ($job -cnotmatch '^[a-f0-9]{32}$') { throw 'Expected the 32-character VPS job ID.' }
& '.\ops\windows\InstallPaytmRestartScanner.ps1' -PlanEvidencePath $plan -Mode Collect -RunId $job
```

Follow the same sudo/copy/receipt prompts. Collect cannot start another transaction. If staging/launch failed before a receipt exists, retain evidence and report the visible non-secret error; do not remove the stage to bypass its guard.

## Outcomes and progress

- `SCANNER_INSTALLED_SCREEN_CLEAR_UNATTENDED_PENDING`: six packages and screen verified; review evidence before maintenance closure/unattended provisioning.
- `SCANNER_INSTALLED_RESTART_FINDINGS_REVIEW_REQUIRED`: installation succeeded and scan completed, but findings need review. Unknown VM microcode is not an automatic reboot instruction; service/session/kernel findings must be considered individually.
- `REVIEW_REQUIRED` with failure: inspect phase and `packageChangeState`. Pre-install stop differs from possible partial changes or installed packages with an incomplete scan. No automatic repair or retry.

Maintenance remains group1 of six until runtime evidence and any restart disposition are reviewed. Unattended supervision, recovery/time gates, Paytm login, fresh quotes and Telegram actions follow; live broker orders are not a paper-return prerequisite. Local tests are not project completion or real Debian runtime proof.

Local verification:59 PowerShell assertions/eight mocked runner workflows,122 Bash assertions/twenty mocked installation transactions, plus51 restart-reader PowerShell and102 shared-maintenance Bash regression assertions. Actual plan hash and all six pinned versions match owner evidence; Apply/Collect payloads, serialized helper presence, documentation commands, JSON and SVG pass checks. No real APT/systemd/VPS installation was run locally.
