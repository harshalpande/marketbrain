# Gateway key custody: next checkpoint G2.3

## Current handoff: host scan diagnostic, 2026-10-27

E196 reviews run `7459b40ca0e749f79eaf8a7f421a0799`: encrypted input and actual non-admin/empty-agent probe passed, but `ssh-keyscan` failed before staging or import. All six source hashes match b3fd126 CRLF checkout bytes. The previous report omitted the native exit, timeout flag and stderr, so the network/client cause is **not established**. Do not reset the account, regenerate keys or rerun the import yet. The installer now checkpoints bounded public scan output before throwing.

Run the following in **PowerShell 7 on the spare laptop**, after updating a clean main checkout. No administrator elevation, PuTTY, Pageant, key path or passwords are needed:

```powershell
& '.\ops\windows\GetPaytmHostScanDiagnostic.ps1'
```

It reads the Windows OpenSSH version and makes one public RSA host-key scan of the existing VPS, with a ten-second process limit. It saves native output, exit status, timing and the unchanged fingerprint check in one `paytm-host-scan-*.json`. Share that file whether the result is `REVIEW_REQUIRED` or `HOST_SCAN_PIN_VERIFIED_KEY_IMPORT_NOT_RUN`. No automatic import follows; no downgrade, new host trust, service change or authentication is attempted. The original PPK/export remain untouched. G1/G2/G3/G4/G5/G6 remains **100/40/0/0/0/0**; accepted checkpoint delta is zero.

The import instructions below are retained for context and are **not the current next command**. A diagnostic pass establishes public host-key retrieval only, not key custody or unattended operation.

## Status and purpose — 2026-10-26

E194 accepts the dedicated Windows account and real credentialed storage/empty-agent probe. Owner has now confirmed the encrypted OpenSSH export was reloaded, prompted for its passphrase and matched the gateway fingerprint. E195 implements the controlled import/verification batch below. **Runtime import is pending; G2 remains40%.** Do not rerun Apply, Recover, account inventory or maintenance. Preserve the account, old archive, original encrypted export and PPK.

The batch lets the **restricted Windows gateway account**, not the administrator or an interactive Pageant session, authenticate with the **existing restricted VPS gateway key**. This is transport identity only, not a Paytm API secret or database-writer password. It requires runtime evidence review before G2.3 can close.

## Confirmed input and key boundaries

Use the verified passphrase-protected **OpenSSH export**, not the PPK. Do not share either file, its contents, passphrase or screenshot of private material. Do not generate a new identity, remove its passphrase, or load it into the administrator's agent. The parser accepts bounded OpenSSH v1, one exact Ed25519 identity, AES-256 CTR/CBC with bcrypt16–1024 rounds, valid salt/ciphertext framing; it rejects plaintext/PPK/wrong-key inputs without decrypting them. A successful header check alone does not prove the passphrase works: actual agent signing and SSH authentication do that later.

Public identity must match `ops/keys/paytm-gateway.pub`: **SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI**. VPS host identity remains the separately verified RSA pin **SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI**. These pins serve different purposes and are not interchangeable.

PuTTYgen supports exporting an existing private key to OpenSSH format, retaining passphrase protection. This is a file-format conversion, not a new server identity. See the [official PuTTY key-conversion documentation](https://www.puttyssh.org/0.83/htmldoc/Chapter8.html). Microsoft describes account-context agent storage and `ssh-add` in its [Windows OpenSSH key-management guide](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement). These capabilities do not prove this laptop's custody, scheduled execution or reboot behavior; those require actual tests.

## Combined implementation and verification

| Area | Required check / boundary |
|---|---|
| Identity | Revalidate accepted account SID, non-admin membership and protected storage. Never recreate/reset the account. |
| Encrypted input | Validate supported format, encryption and exact public identity before loading; reject plaintext or the administrator/wrong key. Never log private material. |
| One-time provisioning | Explicit owner consent; protected staging; import under the exact gateway account with private interactive passphrase entry. Keep passphrase out of commands/environment/reports. Preserve the encrypted offline backup. |
| Custody | Verify the expected identity only and signing in the gateway account; unexpected identities block without clearing keys. Verify the normal operator's agent cannot sign this key before/after. This is context isolation, not protection against a trusted machine administrator; a separate unrelated standard-user test remains unperformed and is explicitly reported. |
| Restricted SSH authentication | Strict host pin, public-key-only authentication, no forwarding of the agent, no shell/PTY, no broad listener or direct Paytm route. Bounded connection/negative tests with owned-process cleanup. No proxy service activation as an incidental action. |
| Failure and revocation | Wrong input, bad passphrase, missing agent, wrong host/key and partial import captured safely. Removal must target only the exact approved key with explicit scope; never `ssh-add -D` or broad service resets. |
| Evidence | One compact JSON containing stage results, timings, public fingerprints and safe error codes; no private-key/passphrase/raw key-list data. |

Acceptance closes G2.3 only after reviewed protected custody and pinned restricted authentication evidence, raising G2 from40% to60%. Engineering tests alone do not close it. Actual reboot/logoff, supervised startup, managed VPS lifecycle and installed-system recovery remain separate checkpoints; do not promise indefinite unattended key persistence before testing.

## Exact sequence and limits

1. Verify the exact accepted E194 report, live account SID/manifest/ACLs/group, current Running/Automatic agent and existing Windows client. Ask IMPORT-GATEWAY-KEY consent and the existing Windows gateway-account password privately. Reuse the corrected short-bootstrap login probe to establish the account and empty agent before staging/import.
2. Fetch only the VPS RSA public host key with bounded `ssh-keyscan`; require its previously verified fingerprint. A scan is never trusted without that comparison. No proxy connection or broker endpoint is used.
3. Create `C:\ProgramData\MarketBrainPaytmGateway\key-custody` once. It inherits no broad permissions and grants only SYSTEM/Administrators FullControl and gateway ReadAndExecute. Stage reviewed worker/helpers/public identity/known-hosts/plan plus an encrypted key copy. The private file has a protected DACL, Administrators ownership, gateway Read and SYSTEM/Administrators FullControl. This retains the established trusted-owner contract without granting the gateway ownership-based ACL control. Source scripts remain outside its writable work directory. All collisions stop; no previous attempt is silently adopted.
4. Start one visible Windows PowerShell5.1 console as the exact gateway account using a short encoded bootstrap reading protected source; no execution-policy change. Native `ssh-add` reads the key passphrase directly from that console. Import, verify single expected identity/signing, remove ONLY that identity using its public key, prove empty/non-signing, then reimport and verify. There are **two SSH-key passphrase prompts**. No `ssh-add -D`, administrator-key changes or shared-agent restart.
5. Reject a deliberately incorrect RSA host pin, then authenticate with the correct pin using public-key-only, strict host checks, explicit public identity and no agent forwarding. Both use `-N -T` and ClearAllForwardings; **no shell, PTY, port listener, tunnel or proxy is started**. Hold the positive authenticated connection for a bounded20seconds and terminate its exact owned process. Only classified native outcomes/elapsed time are retained, not raw logs. Existing server restriction policy is not reread or exhaustively retested here; that remains explicit in the report and later real negative-case acceptance.
6. Once the worker exits successfully, verify the staged encrypted file's hash and delete **only that created copy**. Original export/PPK are untouched. A fresh hidden credentialed process must sign through the agent with the staged private file absent. The operator's separate agent must still fail to sign. Successful staging metadata is retained; no task/service is installed.

The visible worker is required only for one-time private passphrase entry, not unattended operation. It has up to180seconds per native import and the parent has an8-minute worker deadline, with monotonic progress and owned-process-tree cleanup. Use only the key passphrase in the KEY WINDOW; use the Windows account password only in the original administrator window. Keep both windows open until completion; no PuTTY/Pageant or browser-console session is needed.

## Spare-laptop handoff

Open **64-bit PowerShell7 as Administrator**. Do not enable a transcript or screen recording for private entry. Keep application/service settings unchanged.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7 -or -not [Environment]::Is64BitProcess) {
    throw 'Use 64-bit PowerShell 7 as Administrator.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Preserve local changes and stop for review.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
$accountReport = 'C:\MarketBrainData\Review\paytm-gateway-account-20261026-220639-ed64356fd5d84c02b0c156f1fc3ef1b4.json'
if (-not (Test-Path -LiteralPath $accountReport -PathType Leaf)) { throw 'Original accepted account report missing.' }
$encryptedKey = (Read-Host 'Full local path to your VERIFIED ENCRYPTED OpenSSH export (not the PPK)').Trim().Trim('"')
if (-not (Test-Path -LiteralPath $encryptedKey -PathType Leaf)) { throw 'Encrypted export not found.' }
& '.\ops\windows\InstallPaytmGatewayKeyCustody.ps1' -EncryptedKeyPath $encryptedKey -AccountReportPath $accountReport
```

Original window: type **IMPORT-GATEWAY-KEY**, then the existing **Windows marketbrain-gateway account password**. Switch to the newly opened **GATEWAY KEY** window and enter the **SSH-key passphrase twice when prompted**, not immediately as two pasted lines. The second window closes after automatic checks. Return to the original window for **GATEWAY_KEY_CUSTODY_AND_AUTH_PASSED_LIFECYCLE_PENDING** and one `paytm-key-custody-*.json` to share. G2 stays40% until review;60% is only the candidate result.

## Failure and evidence

Failures preserve progress, protected staging and any possibly imported key; no automatic retry/rollback/removal of unrelated identities. **Do not rerun the installer, delete/reset the account, clear keys or change the VPS.** Share only the printed JSON, never encrypted files or passphrases. A stopped import can leave a key loaded; a stop after targeted removal can leave it absent. Worker intent and partial outcomes distinguish these states where observed. A crash during checkpoint writing is not claimed atomic. If the main window is forcibly closed, the worker's own import/SSH timeouts remain bounded, but automatic parent cleanup is not claimed; preserve the private staged folder for review.

After successful worker checks, the encrypted staging copy is deleted and recoverable from the untouched original export; no other private-key file is removed. The folder retains non-secret public/configuration/worker files for subsequent integration. Internal worker JSON stays locally in the account's work directory and is embedded into the single shareable report.

Local E195 verification:112 assertions with9 mocked worker sequences and real SSH `-G` parsing (no connection);97 assertions across14 mocked controller workflows;320 existing account assertions/26 workflows regress successfully. Synthetic ciphertext fixtures are not usable private keys. Tests cover wrong/plaintext/bounded key input, KDF/layout/public pin, native command length/console options, effective no-forward configuration, wrong host/auth classification, targeted revocation, partial failures, exact-copy deletion, original preservation and secret-free reporting. Actual interactive credentialed console, Windows key ACL acceptance, real key import and VPS authentication still need spare evidence.

Implementation references: [OpenSSH private-key format](https://raw.githubusercontent.com/openssh/openssh-portable/master/PROTOCOL.key), [ssh-add signing/removal and tty behavior](https://man.openbsd.org/ssh-add), [Windows credentialed process creation and command-line limit](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithlogonw), [Windows OpenSSH trusted-owner checks](https://raw.githubusercontent.com/PowerShell/openssh-portable/latestw_all/contrib/win32/win32compat/w32-sshfileperm.c). Provider documentation supports the chosen interfaces, not a runtime acceptance claim.

No broker login, quote entitlement, Telegram approval or order authority follows from loading this key. The next downstream stages remain supervisor/task setup, managed proxy lifecycle, real recovery acceptance, then Paytm login and quotes. Live trades remain disabled while returning to paper-account integration.
