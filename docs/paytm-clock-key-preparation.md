# Dedicated encrypted clock-reader key

E280 accepts the VPS policy: 0.214 seconds for effective restriction checks and SSH reload. No key is authorized yet. This step generates a separate Ed25519 identity locally using Windows native ssh-keygen, with bcrypt rounds 64 and a user-entered nonempty passphrase. It never contacts the VPS or installs a task.

## Storage and validation

A unique directory under the current user's LocalApplicationData is created before key generation. Its protected ACL grants the current user, SYSTEM and Administrators full control with inheritance to child files. The encrypted OpenSSH key and public file remain there. The JSON includes their path, public key and fingerprint, never private-key bytes or passphrase. This is operator-side encrypted preparation, not unattended service-account custody.

The existing bounded encrypted-key parser now accepts an optional expected public identity; its default remains the pinned gateway identity. The new controller independently validates Ed25519 wire layout, rejects existing admin/gateway identities, requires bcrypt >=64 rounds and matches encrypted-header public identity to the .pub file. This is format/identity validation, not a remote signing test. Native generation is interactive; keygen prompts are not redirected or recorded. Never pass the passphrase as a command argument.

If the user supplies an empty passphrase or generation fails, the report is REVIEW_REQUIRED and no public identity is accepted for deployment. Files remain in the protected directory for review; do not upload private files or rerun blindly. Encryption is not claimed for a failed report.

Five new parser/controller checks use synthetic encrypted-format bytes and real directory ACL setup, rejecting plaintext/mismatch and preserving the gateway default. Existing 122 key-custody assertions and nine mocked worker sequences passed. No test imported a real key or connected to VPS.

## Spare laptop

Use PowerShell 7 as your normal Windows user. No PuTTY or Pageant required for this step. Enter a new nonempty key passphrase twice when ssh-keygen prompts; save it in your password manager. Do not use or share the VPS password.

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
& '.\ops\windows\NewPaytmClockReaderKey.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-clock-policy-5bcacd66db8749e19d8513323978439d.json'
```

Expected CLOCK_ENCRYPTED_KEY_PREPARED_CUSTODY_AND_AUTHORIZATION_PENDING. Share only the ONE JSON report, not the .openssh private file or passphrase. Keep the generated files in place for the subsequent custody/authorization stage. No rebuild/restart or current key replacement.

G3 remains 80%; overall 14/30 = 46.7%. Key authorization and exact-account unattended custody/worker remain pending before final acceptance.
