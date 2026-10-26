# Dedicated Windows gateway account: controlled recovery

## Current state and purpose — 2026-10-26

**E192 accepts the recovery inventory, not account readiness.** Run `ece79d9aa003448c99ae114f3d1c20ca` captured six checks with zero failures in 0.825 seconds: the Windows account is absent; its old ownership manifest and protected folders remain; the work folder is empty; no profile is registered for the old SID; the existing Windows SSH agent is Running/Automatic. The owner approved recovery after this review.

**E193 prepares one combined Recover run.** It preserves the old folder, creates a new restricted account and fresh storage, and verifies the actual account login. This supersedes all earlier Apply/Verify/inventory-only handoffs for this installation. Do not manually recreate the account, delete folders, reset service permissions or repeat maintenance.

Why: Windows permissions identify an account by SID, not its display name. Recreating `marketbrain-gateway` does not restore its deleted identity. Accepted readiness remains **G1=100%, G2=20%, G3–G6=0%**. Only reviewed successful runtime evidence closes G2.2 and raises G2 to40%; local tests do not advance these checkpoints.

## Exact changes and safeguards

1. Require the exact reviewed inventory (SHA256 `06789E84490F9A524A5C920A433018288899FD33AE3B8A46761EC9DF3817B7FF`). Recheck account absence, old SID/manifest, protected permissions, empty work folder, absence of the old profile and agent configuration. Failed queries are errors, never assumed absence. Reject reparse paths, unexpected files, changed permissions or a recreated account.
2. After **RECOVER-ACCOUNT** consent and two matching private password entries, repeat the checks. Rename the exact `C:\ProgramData\MarketBrainPaytmGateway` directory to its unique sibling `C:\ProgramData\MarketBrainPaytmGateway.recovery-<runId>`. No overwrite or deletion. Checkpoint intent/completion and verify the manifest hash and preserved ACLs after the move.
3. Create a new disabled local non-admin `marketbrain-gateway` account with a new SID, then standard Users membership only. Create fresh SYSTEM/Administrators-owned storage: account read/execute on the root, Modify only in `work`. Record ownership lineage in a non-secret manifest. Enable the new account after storage checks.
4. **Do not stop, start or reconfigure the shared SSH agent.** Recover requires the reviewed Running/Automatic Windows-owned LocalSystem service and checks it again. No keys are imported/removed. The old Stopped/Disabled baseline stays in the archive; the new manifest records the actually preserved Running/Automatic baseline.
5. Launch one bounded hidden probe as the new account with its supplied password. Verify exact SID/non-admin identity, denial of write access to the manifest, write/read/delete in the dedicated work directory, and an empty reachable account-scoped agent. Windows may initialize that profile/start its normal Secondary Logon service during login; startup policy is not changed. Key-list output is classified in memory, never exported.

The corrected credentialed launcher has a380-character command line, guarded below the1,024-character alternate-user launch limit, with non-secret source sent over private UTF-8 stdin. Passwords remain a SecureString credential property, not arguments/environment/files/reports. No source-script file, execution-policy weakening or administrator-identity fallback. Source writing, execution, output bounds and owned-process cleanup are checked; safe stages/outcomes are retained without raw stderr/key lists.

This batch does **not** touch the VPS, application, database, firewall, Paytm credentials, Pageant keys or encrypted PPK. No scheduled task, tunnel activation, broker login or trades. No Docker rebuild/reboot or PuTTY session is needed.

## Complete spare-laptop handoff

Open **64-bit PowerShell7 as Administrator** under your normal Windows login. Leave the application and existing services unchanged.

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
if ($LASTEXITCODE -ne 0) { throw 'Git update failed; do not continue.' }
$inventoryPath = 'C:\MarketBrainData\Review\paytm-gateway-recovery-20261026-132901-ece79d9aa003448c99ae114f3d1c20ca.json'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    throw 'Reviewed inventory missing. Locate the original report; do not regenerate or edit it.'
}
& '.\ops\windows\InstallPaytmGatewayAccount.ps1' -Mode Recover -RecoveryInventoryPath $inventoryPath
```

At the prompts:

1. Type **RECOVER-ACCOUNT** in PowerShell when asked.
2. Enter a new dedicated Windows account password (14+ characters) twice. Keep it privately in your password manager. Do not reuse/share a Windows-admin, VPS, broker or PPK password. Up to three private entry pairs are allowed; Windows policy still applies. SecureStrings are disposed; only non-secret outcome codes are recorded.
3. Expected status: **GATEWAY_ACCOUNT_PROVISIONED_KEY_CUSTODY_PENDING**. This is a candidate result until reviewed, not automatic approval.
4. Share only the printed **`paytm-gateway-account-*.json`**. Keep the archive locally; it is not a file to share.

## Failure and containment

Each step is checkpointed to one exclusively created report, including intent before the directory move. Power loss during a checkpoint is not claimed atomic. Partial results are preserved; **no automatic rollback, retry, deletion or reset**.

- Changed state or an unreviewed report blocks mutation. Confirmed PASSWORD_CONFIRMATION stops can be retried with the same Recover command; it rechecks the baseline.
- After an attempted move/creation or an ambiguous interruption, **do not rerun Apply/Recover, delete the account, restore the folder manually or alter agent permissions**. Share the report first. The archive retains old files/ACLs, but restoring it cannot recreate the deleted account's SID.
- `-Mode Verify` is for a separately reviewed intact installation; it repeats the credentialed probe with the existing dedicated password without resetting account/service configuration. It can initialize the profile and creates/deletes its small probe file. Do not run automatically after partial recovery.
- `-Mode Disable` requires the intact owned manifest/SID/ACL contract and DISABLE-ACCOUNT consent. It disables that account only, without terminating sessions, removing keys/files or stopping the shared service. This is containment, not full rollback or the final gateway kill switch.

## Verification and history

E193:320 account assertions across26 mocked installer workflows (recovery cancellation, report/password failure, drift after input, rename/archive failure, creation failure and probe failure included);29 repair-helper checks with actual temp-directory rename/hash preservation;37 inventory regressions; foundation regression passes79 assertions,12 negative configurations and31 native SSH settings. Counts overlap and are not summed into a unique-test total. Native wrong-identity/transport checks remain included. Real user/service/ACL queries in recovery fixtures are mocked; no actual development-machine account/service change. Spare credentialed execution remains pending.

History remains in the register: E187/E188 input correction; E189 installed account then overlength native launch failure; E190 short-bootstrap correction; E191 owner-deletion inventory; E192 actual residual-state review. Historical Apply/Verify advice is superseded above.

After acceptance: protected gateway-key custody and pinned restricted authentication under this account, then supervised startup and managed VPS lifecycle. Do not assume a Pageant PPK is already usable by Windows OpenSSH.
