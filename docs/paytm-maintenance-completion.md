# VPS maintenance completion: one reviewed reboot and post-boot screen

## Accepted evidence and purpose

E179 accepts scanner Collect report `7e54c5029aca42e3a96c8e0195311723`, source SHA256 `507BD7B7C94C24EA4ACE9A1258BE41106BE79468FC1FC7F5645D92DCF905ECA2`. Collection took **35.83 seconds** (not installation duration). All six scanner packages and all70 earlier targets verified, list-only configuration and origin guards passed, scanner exit0, failure null. No unexpected failed services; the old failed update unit remains historical. The earlier Windows capture failure did not establish a failed installation. Do not reinstall or rerun Collect now.

The scan identifies stale userspace in `cron`, `dbus`, `ssh`, `systemd-logind`, `systemd-timesyncd`, `systemd-udevd` and four sessions. Running/expected kernel both `6.12.95+deb13-amd64`, KSTA1; no reboot marker. A reviewed **whole-VPS normal reboot** refreshes these together, instead of live-restarting SSH/D-Bus/login services piecemeal. It interrupts all VPS workloads and disconnects all PuTTY sessions. It does not reboot Windows or intentionally stop the laptop's MarketBrain service/database. VPS-dependent connectivity is unavailable during downtime.

Missing UCSTA alone does not mean outdated CPU microcode. [needrestart3.11 source](https://sources.debian.org/src/needrestart/3.11-1/needrestart) explicitly disables the microcode check when it detects a VM or container. The new wrapper separately requires recognized VM evidence and no container before treating absent UCSTA as `NOT_ASSESSED_IN_VM_PROVIDER_MANAGED`. Original findings remain visible; unknown environment, explicit bad UCSTA and other scanner failures stay blocked. This is guest maintenance screening, **not host firmware assurance**. No firmware installation or provider-host reboot is attempted.

## Guards and limits

- Before and After are read-only collections, each bounded420s plus5s grace. Exact accepted scanner evidence hash is required for Before. The final After JSON embeds the validated Before evidence, so share only that final file on success.
- Pin VPS SSH host fingerprint and existing proxy/configuration hashes; require root via `marketbrain-admin`, clean dpkg/SSH, no package holds,70 targets and six scanner versions, no unexpected failed services, NTP synchronized, gateway inactive/no listener **and disabled at boot**. Changed or missing evidence stops preparation; no automatic repair.
- Check the prior private scanner configuration archive is root-owned, regular, bounded, readable and attached to the completed job. This is NOT a new backup, current-file comparison, off-host copy, tested restore, full rollback or boot guarantee. Never upload the archive/private log.
- Owner confirms independent HosterDaddy VNC login works now, workloads idle, downtime and same-VPS recovery limitations accepted. Package-process/systemd-job/scheduled-shutdown screens are observations, not atomic exclusion locks. Keep other administrative/package jobs idle throughout. No broad firewall, SSH or scheduled-task changes.
- Separate `REBOOT-VPS` confirmation in PowerShell is required after the fresh precheck. A checkpoint is persisted BEFORE the reboot command is copied. The command is tied to the observed boot ID and a20-minute lease checked using VPS time, rechecks immediate guards and requests normal `systemctl reboot` without force. No delayed timer, install, automatic retry or reboot loop. [systemctl's documentation](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html#reboot) explains that the command queues the reboot; command return/disconnection is not proof it completed.
- After can only observe, even on resume. It requires changed boot ID, later VPS timestamp, successful fresh admin access, fresh baseline/package scan, zero stale service/session/container findings and no unresolved guest findings. Remaining microcode limitation is explicit. It does not certify Windows clock drift, unattended custody/recovery or broker readiness.

## Spare-laptop steps

Keep the independently tested browser/VNC console available. Do not start gateway/tunnel tests or other VPS jobs. Use PowerShell7 and a verified `marketbrain-admin` PuTTY session.

### 1. Pull and start the precheck

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Stop: Git failed or local changes need review.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Stop: expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Pull failed. Do not continue.' }
$scanner = 'C:\MarketBrainData\Review\paytm-scanner-install-20261023-180449-ab36414217f34f62a4b98398b6faf521.json'
if (-not (Test-Path -LiteralPath $scanner -PathType Leaf)) { throw 'Accepted scanner report not found.' }
$beforeReport = & '.\ops\windows\CompletePaytmMaintenance.ps1' -Mode Before -ScannerEvidencePath $scanner
```

1. **PowerShell:** confirm `CONSOLE-READY` only after independently testing VNC login and accepting the stated interruption/recovery limits.
2. When prompted, **PuTTY:** run `sudo -v`, enter your sudo password there. Return to **PowerShell** and press Enter. The read-only precheck is copied.
3. **PuTTY:** paste once. No START/STOP input. Wait for `BEGIN_PAYTM_REBOOT_<id>` through `END_PAYTM_REBOOT_<id>`. Copy the entire block including boundaries, without prompts/progress.
4. **PowerShell:** only after copying the block, press Enter. Findings stop here; share that JSON instead of rebooting. If checks pass and downtime is acceptable, type `REBOOT-VPS` at the explicit prompt.
5. The checkpoint path is printed and the **different, real reboot command** is now copied. Keep this PowerShell window open; `$beforeReport` retains the exact checkpoint path.

### 2. Request the one reboot

**PuTTY:** run `sudo -v` again, then paste the copied reboot command once. It must run within20minutes of the precheck. Expect all PuTTY sessions to disconnect. A guard error means no reboot request; share the visible non-secret error and checkpoint. Do not bypass it or repeat installation.

Reconnect in a new PuTTY session using the same verified host and `marketbrain-admin` key. Never accept an unexpected changed host key. If SSH has not returned after5minutes, inspect the provider VNC console; do not blindly reboot again. Once logged in, run `sudo -v`.

### 3. Collect the post-boot result

In the **same PowerShell window**, run:

```powershell
if (-not $beforeReport -or -not (Test-Path -LiteralPath $beforeReport -PathType Leaf)) {
    throw 'Before checkpoint missing. Use the After-only resume instructions.'
}
& '.\ops\windows\CompletePaytmMaintenance.ps1' -Mode After -BeforeEvidencePath $beforeReport
```

At the sudo-ready prompt, press Enter after `sudo -v` succeeds in the **new** PuTTY session. Paste the new read-only command there. Copy its full `BEGIN_PAYTM_REBOOT_<id>` / `END_PAYTM_REBOOT_<id>` block, return to PowerShell, press Enter. Share the final `paytm-maintenance-completion-...json`; it includes both observations. Expected success: `VPS_REBOOT_VERIFIED_GUEST_SCREEN_CLEAR_UNATTENDED_PENDING`.

If PowerShell closed after reboot, resume **After only**:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$beforeReport = Read-Host 'Paste the exact Before checkpoint JSON path printed before reboot'
& '.\ops\windows\CompletePaytmMaintenance.ps1' -Mode After -BeforeEvidencePath $beforeReport
```

Never substitute the scanner-install JSON for the Before checkpoint. If the boot ID is unchanged or another finding remains, retain the report; do not replay the reboot automatically.

## Progress and next boundary

E179 closes scanner installation/capture acceptance; E180 adds locally tested reboot/postcheck tooling. Maintenance group1 remains open until the real reboot/postcheck report is reviewed. No entire-project percentage increase is inferred. After acceptance, five groups remain: unattended gateway provisioning, recovery/fail-closed/time health, Paytm login, read-only fresh quotes, combined Telegram review. Live broker orders are not required to return to paper integration. One reboot batch is not a guarantee of zero provider/OS findings.

Local verification counts and limits are recorded in [E180](evidence/paytm-maintenance-completion-local-20261023.json). No VPS reboot or package change was executed on the development machine.
