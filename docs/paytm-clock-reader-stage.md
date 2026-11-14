# Keyless VPS clock-reader staging

**E278, 2026-11-15:** Staging report import stopped at CLOCK_STAGE_REPORT_NOT_CONFIRMED because the encoded report was pasted into a confirmation-word prompt. Server result is null; VPS success or failure is not yet established. Do not rerun installation. RecoverPaytmClockReaderReport.ps1 imports only the original run f4990f6148224b49a80fc7bb481eb95f from clipboard/direct paste. Ten import/handoff fixtures pass; no VPS mutation. G3 remains 80%, 14/30 (46.7%).


E277 confirms the proposed names are unused and required tools exist. This stage creates system account marketbrain-health, locked password, its own primary group, root-owned home and empty authorized_keys. It installs /usr/local/libexec/marketbrain-clock-reader.py. No SSH configuration reload, authorized key, gateway restart, Windows account/task or broker access is created.

The reader accepts exactly marketbrain-clock followed by a 32-character lowercase hex nonce. It invokes a fixed timedatectl command without a shell and returns the existing MB_CLOCK_V1 nonce/time/NTP receipt. A later reviewed SSH forced-command policy must enforce this program; installing it alone is not proof of SSH restrictions.

The installer checks the pinned VPS RSA host fingerprint, refuses existing account/home/program, checks parent ownership, creates files exclusively, verifies locked password and single group, then uses runuser to test the allowed command and rejection of id. Failure leaves partial state for review rather than deleting anything. Do not rerun blindly. It adds no sudo grant; existing system-wide policy is not audited by this stage.

Local verification: seven Python tests (reader command/timeout/status and mocked installer success/collision/failed denial), four PowerShell handoff tests (success, wrapped output, server failure, wrong run). POSIX account/filesystem behavior must still pass on the VPS. Local tests do not claim actual installation acceptance.

## Steps

1. Open the verified PuTTY session as marketbrain-admin. Run sudo -v and enter the administrator password there. Keep this window open.
2. On the spare laptop, use PowerShell 7 to pull main and run the staging controller below. It copies a complete command to your clipboard; do not copy anything else before pasting it into PuTTY.
3. Paste that command into the PuTTY terminal and press Enter if needed. There is no START-TEST prompt. Wait for MB_CLOCK_STAGE_REPORT: followed by encoded report text.
4. Copy the complete report line only. Return to PowerShell and paste the complete report at the prompt, or press Enter to read the clipboard. The parser tolerates line-wrap whitespace.
5. Share the one JSON printed by PowerShell. Expected CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING. On failure retain report and do not delete the account or rerun.

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
& '.\ops\windows\StagePaytmClockReader.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-unattended-preflight-20261115-034000-c0e727fb8ab647ddb6bf02e39ba2197c.json'
```

No application rebuild/restart needed. Staging normally takes seconds after the PuTTY command; sudo authentication occurs before it. Existing admin login remains available.

Remaining: restricted SSH policy and dedicated key, Windows exact-account credential custody and worker, combined unattended lifecycle acceptance. G1/G2 100%, G3 80%, G4-G6 0%; overall 14/30 (46.7%).

## Recovery for E278 only

Run RecoverPaytmClockReaderReport.ps1 with -EvidencePath pointing to the failed paytm-clock-reader-stage-f4990f6148224b49a80fc7bb481eb95f.json. At its prompt paste the original MB_CLOCK_STAGE_REPORT line from PuTTY, or press Enter after copying that line to the clipboard. Do not run the installer again. If the original report is unavailable, stop and report that fact; a separate read-only VPS inspection is needed. The screenshot is not used to reconstruct authoritative payload bytes.

This imports historical installation evidence, not a fresh VPS state check. Source run identity and boolean result contracts are checked. Share the single recovery JSON even if it reports server failure. Success status is CLOCK_STAGE_REPORT_RECOVERED_INSTALLATION_REPORTED_PASSED. No password, Pageant key or SSH connection is needed for recovery.
