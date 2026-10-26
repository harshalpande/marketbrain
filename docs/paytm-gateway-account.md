# Dedicated Windows gateway account and agent setup

## Purpose and current evidence

**Current, 2026-10-26 E189/E190 — VERIFY ONLY:** run `5effeeb6993d484fa70ac49555e88aa4` created the account and protected folders, enabled the account, started/configured the agent and passed ownership/ACL/membership/service postchecks. Password confirmation succeeded on attempt2. It then failed at `Process.Start` before the alternate-account probe ran (`0x80070057`), after110.512s including owner input. **Do not repeat Apply, recreate the account or reset its password.** Use the existing dedicated password with the Verify handoff below.

The old full-source encoded argument exceeded7,000 characters. [Microsoft's alternate-user launch API](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithlogonw) limits its command line to1,024 characters; [.NET's Windows process implementation](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Diagnostics.Process/src/System/Diagnostics/Process.Windows.cs) uses that credentialed launch path. This identified contract violation is consistent with the parameter error; actual corrected alternate-user execution is still pending. The new launcher uses a380-character command line (including executable/quotes/NUL allowance) and sends non-secret source over a private UTF-8 stdin pipe. Passwords remain only in the credential property. No probe script is written to disk, no execution-policy weakening or fallback to administrator identity.

E190 verifies236 assertions/17 mocked workflows and actual native bootstrap/pipe/capture execution, including large/Unicode input, malformed/empty/array/oversized output, nonzero exit, syntax/start failure and timeout cleanup. The previous tests mocked the credentialed launcher and exercised a different same-user encoded-command path; they could not expose its shorter API limit. That test gap is now covered by an exact production launch-contract check and shared native transport tests. These local tests do not authenticate as the spare's account. Child check outcomes and launch stages are now retained before acceptance validation, without raw stderr or key lists.

Accepted group percentages remain100/20/0/0/0/0. Six setup stages completed, but G2.2 requires the final real-account probe before G2 can become40%.

**2026-10-24 E187/E188:** spare run `962eecffb56049c5ae000466d47921b1` stopped at private password confirmation in20.248s, before account creation or service changes. Administrator, client-tool and actual service-control checks passed. The old combined error cannot establish whether the password was short or confirmation differed; do not infer an administrator/password-policy failure. No partial account/folder needs cleanup. The corrected launcher separates those outcomes, labels the stage correctly, and allows up to three private entry attempts before stopping. Retry this account step at the next login after pulling the fix; no work is required tonight. G2 remains20% pending real account/probe evidence.

E185 accepts the spare's foundation report:79 assertions,12 negative cases,31 client settings,2.335s, failure null. **Do not rerun foundation or VPS maintenance.** The [progress baseline](paytm-readiness-progress.md) is G1=100%, G2=20%, G3–G6=0%.

E186 implements one controlled provisioning batch. This is a real Windows account/service change, unlike the preceding configuration-only test. Why: unattended transport must have a consistent non-admin identity and a verified place to run before we entrust it with the restricted gateway key. Existing application/Docker operation remains under its existing account; this does not migrate the application.

## Exact changes and verification

- Create **Windows local user `marketbrain-gateway`**, initially disabled, with a new owner-entered password. This is a different account from the identically named Linux user on the VPS. Do not reuse a Windows-admin, VPS, broker or PPK password. No administrator-group membership; only the standard Users group. Windows password-expiry policy remains unchanged and must be considered later for scheduled operation.
- Create **`C:\ProgramData\MarketBrainPaytmGateway`** with SYSTEM/Administrators full control and gateway-account read/execute. Its `work` child grants that account Modify. No inherited broad access, unknown ACEs or reparse paths. Store a non-secret ownership manifest with SID and original agent state. The account cannot modify this manifest. No existing account/folder is adopted, reset or overwritten.
- Set the **existing Windows `ssh-agent` service** to Automatic and start it. This is system-wide. The expected original service is stopped/disabled and runs the Windows-owned executable as LocalSystem. The script first checks real SCM query/change/start access, not just the UAC admin flag. It does **not** install/start OpenSSH Server (`sshd`).
- Enable the new account and run one hidden, bounded, private probe with its supplied password. Built-in Windows PowerShell5.1 avoids dependency on another user's PowerShell7 installation. Windows may initialize the new user profile/start its normal Secondary Logon service as part of this login; the script never changes Secondary Logon startup policy.
- Verify actual account SID/non-admin token, inability to open the protected manifest for writing, write/read/delete in its own work folder, and an empty reachable account-scoped SSH agent. `ssh-add -l` output is classified in memory; key lists are never emitted. No key is imported yet. This is an empty-agent/identity test, not proof of stored-key persistence or wrong-user denial after key import.

The launcher inspects targets and all local group queries before writing, prints exact scope, and requires **PROVISION-ACCOUNT**. Password input is secure/local and confirmed twice (minimum14 characters plus Windows policy). A short new password and a confirmation mismatch have different messages. Up to three entry pairs are allowed; Ctrl+C cancels. Rejected inputs and all confirmations are disposed immediately; the accepted password is disposed at launcher exit. Only attempt numbers/outcome codes are recorded, never content or exact lengths. Comparison is exact, case-sensitive, with no trimming or normalization. It is passed to Windows login through the in-process SecureString property, never shell arguments/environment/report. No plaintext password or key file is created by the script. Input validation is not proof that Windows account/password policy or alternate-account login will accept it; those remain runtime checks.

There is no VPS/Paytm connection, firewall change, scheduled task, automatic gateway, broker login, account/writer unlock, order or fill. Success is **GATEWAY_ACCOUNT_PROVISIONED_KEY_CUSTODY_PENDING**. If reviewed and accepted, G2.2 closes and G2 becomes40%; G3–G6 remain unchanged.

## Current recovery: verify the existing account on the spare laptop

1. Open **PowerShell7 as Administrator** on the spare. Continue using your normal Windows login; do not sign out. No PuTTY/Pageant/VPS commands, no rebuild or reboot.
2. Run:

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7 -or -not [Environment]::Is64BitProcess) {
    throw 'Use 64-bit PowerShell 7 as Administrator.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Close this window and open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Preserve local changes and stop for review.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed; do not verify.' }
& '.\ops\windows\InstallPaytmGatewayAccount.ps1' -Mode Verify
```

3. Enter the **existing `marketbrain-gateway` Windows account password successfully confirmed in run5effeeb6**, not a new password, administrator password or PPK passphrase. There is no PROVISION-ACCOUNT prompt in Verify. Do not share it. If forgotten, stop and request a reviewed recovery; do not reset/recreate the account blindly.
4. Verify checks the owned account/manifest/ACLs/membership and agent state, then runs the hidden probe. The probe creates/deletes only its own small test file; normal Windows login/profile bookkeeping may occur. Account/password/service configuration is not changed. Progress75/85/100%; child execution wait60s after startup plus bounded pipe/cleanup waits. No START-TEST/STOP/SERVER_READY, PuTTY or clipboard interaction. Exact elapsed time is recorded, not promised.
5. Share only the printed **`paytm-gateway-account-*.json`** from `C:\MarketBrainData\Review`—whether pass or fail. It includes completed steps/timing, current failure stage and non-secret error identifiers. Installed manifest/profile are not files to share.

## Failure, recheck and containment

**Current E189 overrides the earlier E187 input-only retry advice:** an installation now exists and passed postchecks. Resume with **Verify only**. Preserve it even if verification fails. The report now distinguishes parent launch stages from child IDENTITY/PROTECTED_STORAGE/WORK_DIRECTORY/AGENT_QUERY stages and retains safe negative child outcomes. Missing/unreachable/non-empty agent remains a failure, never silently accepted.

The one report is checkpointed before/after steps through an exclusively created owned file. A process interruption can leave partial account/service state; power loss during a checkpoint is not claimed atomic. Partial installations are preserved, not deleted or silently adopted. **Exception for confirmed input-only stops:** E187 proves no account/folder/service changes; a corrected Apply is appropriate. The new launcher also identifies failures in PASSWORD_CONFIRMATION as pre-change stops that can be retried later, with fresh absence checks. This is not permission to rerun after creation/service/probe failures. For those or ambiguous interruptions, **do not repeat Apply**, reset passwords, weaken ACLs, alter service permissions or delete the folder. Share the report first. Completed maintenance and foundation acceptance do not regress merely because installation needs review.

`-Mode Verify` does not create users/change services/reset passwords; it validates the owned SID/manifest/ACLs/membership and repeats the exact-account probe using the existing dedicated password. It does create/delete that small probe file and can cause normal Windows profile/login bookkeeping. Use only when directed, not as an automatic retry after an incomplete Apply.

`-Mode Disable` requires an intact owned manifest/SID/ACL contract and **DISABLE-ACCOUNT** confirmation; it disables that exact local account. It does not delete files, terminate existing sessions, remove keys, restore shared ssh-agent startup settings or change the VPS. It is account containment, **not** the final gateway kill switch or a full rollback. Original stopped/disabled agent state is retained for a separately reviewed restoration only after checking for other consumers. Shared service changes are never reversed blindly.

## Verification and references

E188 correction verification:199 assertions across16 mocked full-launcher workflows, including short/mismatched passwords followed by success, success on the third attempt, bounded exhaustion, interrupted input, SecureString disposal and secret-free console/report output. Direct comparison checks cover empty/missing input,13/14 boundary, unequal lengths, case/space differences and Unicode. Native wrong-identity probe and ACL round-trip remain included. This is local engineering verification, not spare provisioning acceptance.

Local verification:99 assertions;10 mocked full-launcher workflows; native Windows security-descriptor round-trip; built-in Windows PowerShell wrong-SID probe rejects before filesystem/agent access; real read-only SCM access probe reports denied for the non-elevated development process. Mocks exercise consent/collision/no-write paths, already-present Users membership, service/group-query denials, partial service/probe failures, Verify and owned-account Disable. No actual account or service was changed on the development laptop; real alternate-account login and provisioning await spare evidence.

[Microsoft local-account creation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1) and [Windows OpenSSH key custody](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement) inform the implementation. Documentation does not establish this machine's permissions or credential persistence. Next, after acceptance: encrypted-key provisioning and pinned restricted authentication under this account, then production supervision/task and managed VPS lifecycle. No assumption that the existing Pageant PPK is already usable by Windows OpenSSH.
