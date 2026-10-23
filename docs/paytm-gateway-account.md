# Dedicated Windows gateway account and agent setup

## Purpose and current evidence

E185 accepts the spare's foundation report:79 assertions,12 negative cases,31 client settings,2.335s, failure null. **Do not rerun foundation or VPS maintenance.** The [progress baseline](paytm-readiness-progress.md) is G1=100%, G2=20%, G3–G6=0%.

E186 implements one controlled provisioning batch. This is a real Windows account/service change, unlike the preceding configuration-only test. Why: unattended transport must have a consistent non-admin identity and a verified place to run before we entrust it with the restricted gateway key. Existing application/Docker operation remains under its existing account; this does not migrate the application.

## Exact changes and verification

- Create **Windows local user `marketbrain-gateway`**, initially disabled, with a new owner-entered password. This is a different account from the identically named Linux user on the VPS. Do not reuse a Windows-admin, VPS, broker or PPK password. No administrator-group membership; only the standard Users group. Windows password-expiry policy remains unchanged and must be considered later for scheduled operation.
- Create **`C:\ProgramData\MarketBrainPaytmGateway`** with SYSTEM/Administrators full control and gateway-account read/execute. Its `work` child grants that account Modify. No inherited broad access, unknown ACEs or reparse paths. Store a non-secret ownership manifest with SID and original agent state. The account cannot modify this manifest. No existing account/folder is adopted, reset or overwritten.
- Set the **existing Windows `ssh-agent` service** to Automatic and start it. This is system-wide. The expected original service is stopped/disabled and runs the Windows-owned executable as LocalSystem. The script first checks real SCM query/change/start access, not just the UAC admin flag. It does **not** install/start OpenSSH Server (`sshd`).
- Enable the new account and run one hidden, bounded, private probe with its supplied password. Built-in Windows PowerShell5.1 avoids dependency on another user's PowerShell7 installation. Windows may initialize the new user profile/start its normal Secondary Logon service as part of this login; the script never changes Secondary Logon startup policy.
- Verify actual account SID/non-admin token, inability to open the protected manifest for writing, write/read/delete in its own work folder, and an empty reachable account-scoped SSH agent. `ssh-add -l` output is classified in memory; key lists are never emitted. No key is imported yet. This is an empty-agent/identity test, not proof of stored-key persistence or wrong-user denial after key import.

The launcher inspects targets and all local group queries before writing, prints exact scope, and requires **PROVISION-ACCOUNT**. Password input is secure/local and confirmed twice (minimum14 characters plus Windows policy). It is passed to Windows login through the in-process SecureString property, never shell arguments/environment/report. No plaintext password or key file is created by the script.

There is no VPS/Paytm connection, firewall change, scheduled task, automatic gateway, broker login, account/writer unlock, order or fill. Success is **GATEWAY_ACCOUNT_PROVISIONED_KEY_CUSTODY_PENDING**. If reviewed and accepted, G2.2 closes and G2 becomes40%; G3–G6 remain unchanged.

## Run once on the spare laptop

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
if ($LASTEXITCODE -ne 0) { throw 'Git update failed; do not provision.' }
& '.\ops\windows\InstallPaytmGatewayAccount.ps1' -Mode Apply
```

3. Read the scope, type **PROVISION-ACCOUNT**, then enter and confirm a **new dedicated Windows account password**. Save it privately in your password manager; don't share it. It is not the PPK passphrase. Normal password prompts display no password text.
4. Wait for progress20/30/45/55/65/75/85/100%. Agent running-state wait is15s; private process probe maximum60s plus cleanup. No START-TEST/STOP/SERVER_READY or clipboard interaction. Exact elapsed time is recorded, not promised.
5. Share only the printed **`paytm-gateway-account-*.json`** from `C:\MarketBrainData\Review`—whether pass or fail. It includes completed steps/timing, current failure stage and non-secret error identifiers. Installed manifest/profile are not files to share.

## Failure, recheck and containment

The one report is checkpointed before/after steps through an exclusively created owned file. A process interruption can leave partial account/service state; power loss during a checkpoint is not claimed atomic. Partial installations are preserved, not deleted or silently adopted. On error, **do not repeat Apply**, reset passwords, weaken ACLs, alter service permissions or delete the folder. Share the report first. Completed maintenance and foundation acceptance do not regress merely because installation needs review.

`-Mode Verify` does not create users/change services/reset passwords; it validates the owned SID/manifest/ACLs/membership and repeats the exact-account probe using the existing dedicated password. It does create/delete that small probe file and can cause normal Windows profile/login bookkeeping. Use only when directed, not as an automatic retry after an incomplete Apply.

`-Mode Disable` requires an intact owned manifest/SID/ACL contract and **DISABLE-ACCOUNT** confirmation; it disables that exact local account. It does not delete files, terminate existing sessions, remove keys, restore shared ssh-agent startup settings or change the VPS. It is account containment, **not** the final gateway kill switch or a full rollback. Original stopped/disabled agent state is retained for a separately reviewed restoration only after checking for other consumers. Shared service changes are never reversed blindly.

## Verification and references

Local verification:99 assertions;10 mocked full-launcher workflows; native Windows security-descriptor round-trip; built-in Windows PowerShell wrong-SID probe rejects before filesystem/agent access; real read-only SCM access probe reports denied for the non-elevated development process. Mocks exercise consent/collision/no-write paths, already-present Users membership, service/group-query denials, partial service/probe failures, Verify and owned-account Disable. No actual account or service was changed on the development laptop; real alternate-account login and provisioning await spare evidence.

[Microsoft local-account creation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1) and [Windows OpenSSH key custody](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement) inform the implementation. Documentation does not establish this machine's permissions or credential persistence. Next, after acceptance: encrypted-key provisioning and pinned restricted authentication under this account, then production supervision/task and managed VPS lifecycle. No assumption that the existing Pageant PPK is already usable by Windows OpenSSH.
