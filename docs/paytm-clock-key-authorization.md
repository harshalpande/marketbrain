# Authorize the dedicated clock public key

E281 accepts encrypted operator-side key preparation: fingerprint SHA256:TqoeCxI+3t+k2XTi8E6f+7iX4HCyhc1gshoZqnfyaX0. Only the public key appears in this installer; no private key or passphrase is transferred.

## Change and checks

Recheck pinned host identity, root-owned reader hash and exact installed policy content; verify effective policy and UsePAM=yes, unchanged account shell/home and single group, and locked password. Refuse any nonempty authorized_keys. Atomically replace only that empty file with the exact reviewed public key, using restrict and the same fixed forced command in addition to the effective Match policy. No SSH reload is needed.

The file is root-owned 0644: it contains a public key, and sshd must be able to read it as the target account. A runuser read check verifies access. There is no password unlock, new shell authority, forwarding permission, clock modification or gateway restart. If post-write checks fail, restore an empty file only if the installed content still exactly matches this operation; report concurrent drift rather than overwriting it. Preexisting temporary files are never deleted.

Five Python tests cover success, existing authorization refusal, preexisting temporary-file preservation, unreadable-file rollback and PAM mismatch. Five PowerShell fixtures cover valid/wrapped/direct input, failed server receipt and wrong-run rejection. They mock VPS behavior; the spare receipt is required. Actual SSH authentication/command denial over the network is explicitly not tested by this installer. Windows exact-account custody and worker deployment remain pending afterward.

## Spare-machine steps

Open verified PuTTY as marketbrain-admin and keep it open. In PowerShell 7:

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
& '.\ops\windows\AuthorizePaytmClockReaderKey.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-clock-key-preparation-c192c546fbc2470f961341ea21f52266.json'
```

When the command is copied, in PuTTY type sudo -v and enter the administrator password there. Paste the copied command; do not copy anything else first. Wait for MB_CLOCK_KEY_REPORT: and copy that complete line into the waiting PowerShell prompt. No START-TEST prompt and no key passphrase required in this step. Share the one JSON on success or failure. Do not rerun authorization blindly.

Expected CLOCK_PUBLIC_KEY_AUTHORIZED_LOGIN_AND_CUSTODY_PENDING. Keep the encrypted private key locally. No application rebuild/restart. G3 remains 80%, overall 14/30 (46.7%); explicitly announce G3 100% only after remaining acceptance.
