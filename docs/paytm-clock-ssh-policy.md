# Keyless clock-reader SSH policy

E279 recovers original run f4990f6148224b49a80fc7bb481eb95f: account/password/program/allowed-command/denied-command/keyless checks passed in 0.237 seconds. Recovery did not make a fresh VPS inspection; the next installer does.

## Scope

Create only /etc/ssh/sshd_config.d/00-marketbrain-health.conf with Match User marketbrain-health. Force the root-owned Python clock reader, require public-key authentication, disable passwords, interactive authentication, host/GSSAPI authentication, all forwarding, terminal, tunnel and user RC; use only the empty root-owned authorized_keys and disable CA/principal alternatives. No key is installed and password remains locked.

ForceCommand does not itself disable forwarding; DisableForwarding is explicitly included per [OpenSSH documentation](https://man.openbsd.org/sshd_config#ForceCommand). The installed Debian sshd validates syntax and effective values before reload, so unsupported or ignored directives fail closed.

The installer rechecks pinned host identity, reader hash, root-owned files, account identity and keyless/password state. It refuses an existing policy file. It compares full effective settings for administrator, gateway and root in the current SSH connection address context before/after. This is not proof for every hypothetical source-address Match branch. Syntax/effective checks precede ssh.service reload; existing sessions should remain connected. Keep the current verified administrator session open and retain the previously verified VNC recovery option.

On failure after file creation it removes only the exact unchanged newly created file, checks syntax and other-account restoration, reloads and checks service activity. Concurrent policy changes or failed rollback require review. No generic cleanup, account removal, SSH restart or gateway restart. The original config is not overwritten. Reports keep safe booleans/errors rather than full SSH configuration or credentials.

## Verification

Five Python tests model success, preexisting file refusal, missing effective restriction, other-account drift and reload failure/rollback. Five PowerShell fixtures cover valid, wrapped, direct-pasted, failed and wrong-run reports. These ten local tests mock remote behavior. Runtime acceptance still requires the installed sshd checks; actual collector login/denial tests require the later dedicated-key stage.

## Run

Open PuTTY as marketbrain-admin and keep it open. In PowerShell 7 on the spare laptop:

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
& '.\ops\windows\InstallPaytmClockSshPolicy.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-clock-reader-recovery-4030243548354550b4fd49989d49dab2.json'
```

When it says the command is copied, in PuTTY type sudo -v, enter the password there, then paste the clipboard command. Do not copy anything else first. No START-TEST prompt. Copy the full MB_CLOCK_POLICY_REPORT: output line and paste it directly into the waiting PowerShell prompt. Share the single resulting JSON even on failure. Do not rerun installer blindly.

Expected CLOCK_SSH_POLICY_INSTALLED_KEYLESS_CUSTODY_PENDING. No application rebuild or restart. G3 80%; 14/30 (46.7%). Dedicated-key custody and unattended worker/lifecycle remain pending. Explicitly announce G3 100% only when accepted evidence closes G3.5.
