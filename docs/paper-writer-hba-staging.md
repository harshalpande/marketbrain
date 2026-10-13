# Guarded paper writer authentication staging

The accepted read-only plan verified the actual PostgreSQL file and application connection on the spare laptop. This next package backs up and applies only the fixed writer restriction prefix, then verifies new connections. It does not enable writer LOGIN, create credentials, change firewall rules, rebuild the application, or enable trades.

## Accepted spare rehearsal

E124 accepts `paper-hba-rehearsal-20261013-122150-14a7df604d5f.json`: 434 workflow assertions and 134 separate descriptor checks passed in 34.540s on PowerShell 7.6.6 / .NET 10.0.12. All five script hashes match the reviewed Windows checkout. Legacy permissions were preserved, original bytes were restored and generated fixtures were cleaned up. No real PostgreSQL file or database was touched. The owner authorized actual guarded staging next. Do not repeat this accepted rehearsal for the unchanged scripts.

The frozen staging package remains 60% because actual file staging and fresh database/application connection verification are still pending. The earlier failure and correction below explain the retained safeguards, not a current rehearsal blocker.

## Permission comparison safeguards

E123 reviews `paper-hba-rehearsal-20261013-105852-b5f2d5a7f6c5.json`: the spare stopped before real staging, after two assertions in1.498s. Contents, owner and group matched. The temporary descriptor acquired `DiscretionaryAclAutoInherited`; both descriptors had three entries, but the report did not prove entry equality. All four source hashes match the Windows checkout. Generated legacy-file tests now reproduce that flag transition and also show it on the replaced target.

The correction permits only that single Windows-managed descriptor bit to differ during explicit owned replacement, post-validation and recovery checks. After clearing the bit in memory, the **entire binary descriptors must match**. Owner, group, ACE bytes/order, allow/deny, trustee, rights, per-entry inheritance, protection and every other descriptor flag remain checked. No sorting, rights merging or permission rewriting is used. Reviewed-plan hashes, backup fingerprints and pre-first-edit target checks remain exact. Matching entry counts alone never authorize acceptance.

Accepted metadata differences are recorded in `aclMetadataObservations` for staging/recovery and `legacyAclRegression` in the rehearsal. Windows documents the flag as resource-manager-managed inheritance metadata, separately from inheritance protection. [Microsoft control flags](https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.controlflags?view=net-10.0).

For future changes to the staging scripts, the rehearsal writes one `paper-hba-rehearsal-*.json` on success or a caught test failure, including runtime versions, source hashes, completed assertions, elapsed time and failure phase. Drift diagnostics compare content, owner, group, access permissions, control flags and access-rule counts without including original file contents, raw security descriptors, credentials or account SIDs. The exact permission comparison remains mandatory. Early output-directory/import failures may prevent report creation. The following command is a regression reference, not the current handoff:

```powershell
& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File '.\ops\windows\TestPaperWriterHbaStage.ps1' -OutputDirectory 'C:\MarketBrainData\Review'
if ($LASTEXITCODE -ne 0) { throw 'Rehearsal failed. Share its JSON; do not apply the real change.' }
```

This command needs no database credentials and never opens PostgreSQL or Docker. Expected failure cases in the mocked workflows are assertions, not real configuration changes. Success is `REHEARSAL_PASSED_NO_REAL_CHANGES`. Future changed-script rehearsals require review before actual staging. Failed generated fixtures remain in the unique temporary test directory for investigation. Successful fixtures are removed, while the summary is retained. No existing application data is removed.

The revised rehearsal includes the existing20 mocked staging and4 recovery scenarios, descriptor mutation tests and a real generated three-entry legacy ACL. It exercises replacement, independent recovery and automatic rollback after an injected failure. Test-only legacy ACL creation is never imported by production scripts. E123 records local measurements; E124 accepts the spare correction.

E123 local results:434 workflow assertions and134 descriptor checks pass on both PowerShell5.1 and7.6.6, in123.525s and517.521s respectively. Separate293 planning and40 restriction regressions pass. Laptop timings can differ; the tests report progress and measured elapsed time.

## Why each step is needed

| Step | Purpose | Success establishes |
|---|---|---|
| Fresh identity and file checks | Avoid applying an old plan to a changed server or file | The database, application route, bytes and permissions still match the reviewed report |
| Protected local backup | Retain a recoverable original before the first edit | Original bytes, candidate bytes and owner/group/access-permission metadata can be independently read and hash-checked |
| Exact file replacement | Add only the four reviewed writer rules | Existing rules remain byte-for-byte intact beneath the prefix |
| Permission and PostgreSQL checks | Detect file-access problems or rejected syntax | Recorded owner/group/DACL unchanged, zero parse errors, expected rule count and writer still NOLOGIN |
| Fresh application connection | Existing pooled connections do not prove new connections work | A new read-only connection from the application container still reaches the expected database |
| Guarded recovery | Recover from failed post-change validation without overwriting unrelated edits | Original bytes/permissions restored, with connection revalidation reported separately |

The proposed rules allow the dedicated writer to authenticate only to `marketbrain` through IPv4 loopback, subject to its credentials and database privileges. Other database/replication and IPv4/IPv6 routes for that role are rejected. NOLOGIN remains in force, so this is not an authentication-success test or writer activation. Existing application/admin rules are retained.

## Spare laptop handoff

The owner authorized the procedure below after E124 rehearsal review. This changes the real authentication configuration on the spare laptop only; it is not another synthetic test. No development-machine execution is authorized.

Use elevated PowerShell 7. Leave the existing application and PostgreSQL running. Do not edit PostgreSQL configuration, change permissions, restart services or run another staging/recovery command concurrently. A named mutex prevents overlapping instances of these scripts, not unrelated administrator tools.

1. Pull the committed change with a clean worktree. No Docker rebuild is needed.
2. Confirm that the reviewed plan below exists. E124 already verifies the unchanged staging scripts; do not repeat the completed rehearsal. Do not run Apply again after a successful or interrupted staging attempt without reviewing its report.
3. Run `SetPaperWriterHbaRestriction.ps1 -ReviewedPlanPath <accepted report> -Apply`. The accepted report is `paper-writer-hba-plan-20261013-134028-6886987b4327.json`, SHA256 `C5D159FB8703627F2560BD139EF9AD00278197C52D4021B326C2C78C44B1FD64`.
4. Enter PostgreSQL administrator credentials locally, then type `APPLY WRITER RESTRICTION` only after reading the confirmation. Without `-Apply`, the script performs preflight only.
5. Share the one printed `paper-writer-hba-stage-*.json`. Do not share the private recovery directory.

Success is `HBA_RESTRICTION_STAGED_WRITER_DISABLED`. This closes file staging only after review of spare evidence. It does not resolve the effective firewall-access findings or complete the application writer.

Run this block after pulling the reviewed documentation commit. The runner performs fresh checks before any replacement and prompts locally for the PostgreSQL administrator, not the Windows login. Do not send credentials in chat.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 with Run as administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$planPath = 'C:\MarketBrainData\Review\paper-writer-hba-plan-20261013-134028-6886987b4327.json'
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw 'Reviewed HBA plan missing. Stop and share this message.' }
if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -cne 'C5D159FB8703627F2560BD139EF9AD00278197C52D4021B326C2C78C44B1FD64') {
    throw 'Reviewed HBA plan hash differs. Do not apply.'
}
Write-Host 'Guarded real HBA staging: private backup, writer rules, fresh connection checks. No writer activation.' -ForegroundColor Cyan
& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File '.\ops\windows\SetPaperWriterHbaRestriction.ps1' -ReviewedPlanPath $planPath -Apply
if ($LASTEXITCODE -ne 0) {
    throw 'Staging stopped. Share the printed stage JSON; do not rerun Apply or delete the private backup.'
}
```

No automatic retry or broad cleanup is performed. A stopped container produces `HBA_STAGE_APPLICATION_NOT_RUNNING`; multiple matches and malformed responses have separate errors. Drift from the accepted plan stops before replacement. Do not bypass the hash/identity checks; review changed evidence first.

After an eventual rollback, Windows may retain the metadata bit even though original permissions and bytes are restored. The next apply still requires an exact reviewed-plan fingerprint; if that changed, refresh and review the plan instead of bypassing its guard. Neither the failed nor the accepted spare rehearsal modified the real file. A real PostgreSQL restart, changed identity or file/permission change can invalidate the saved plan; report that stop rather than bypassing the guard.

## Backup and recovery

Private backups are stored beneath `C:\MarketBrainData\Secrets\PaperWriterHba\<run ID>`. Each directory contains `original.bin`, `candidate.bin` and `recovery.json`. The last file records the target, hashes and original owner/group/DACL. These are file-configuration backups, not database, historical-data or model backups. Access is restricted to the creating Windows identity and SYSTEM; use the same administrator account for recovery. Backups are retained, not automatically deleted.

Before replacement, the script verifies all three files and checkpoints their directory in the shareable report. It uses same-volume file replacement without ignoring metadata errors, followed by byte and permission readback. It does not claim a transactional compare-and-swap against unrelated administrators, audit-SACL validation or immunity to machine/power loss. Avoid concurrent configuration work.

Failed post-change validation triggers file recovery only if the current bytes and recorded permissions still match the owned candidate. `FAILED_ROLLED_BACK` means both file restoration and fresh admin/application connections passed. `FAILED_RECOVERY_REVIEW_REQUIRED` or `MANUAL_RECOVERY_REQUIRED` requires investigation; no further overwrite is attempted. A missing target or unknown contents/permissions is not silently repaired.

For an interrupted process, do not blindly rerun apply. Review its report and the private directory, then use:

```powershell
$recoveryParameters = @{
    ReviewedPlanPath = 'C:\MarketBrainData\Review\paper-writer-hba-plan-20261013-134028-6886987b4327.json'
    RecoveryDirectory = Read-Host 'Paste the private recovery directory printed by the staging run'
}
& '.\ops\windows\RestorePaperWriterHbaRestriction.ps1' @recoveryParameters
```

This independent recovery path needs no database password or working application container. It validates the backup against the accepted plan and requires `RESTORE ORIGINAL HBA` confirmation. `ORIGINAL_FILE_VERIFIED_CONNECTION_RECHECK_REQUIRED` proves only the local file state; fresh database/application verification is still required. Unknown changes or an absent target require manual review. Never publish the private backup contents.

## Verification and remaining gates

The frozen package covers protected backup, exact prefix replacement, owner/group/DACL preservation, fresh PostgreSQL/application checks, guarded automatic rollback, independent file recovery, and one shareable report. Local tests use actual Windows temporary-file/ACL operations with Docker, PostgreSQL, admin checks and credential input mocked. PowerShell 5.1 verification on the development host does not replace the PowerShell 7 rehearsal and actual runtime validation on the spare.

Live writer LOGIN, effective firewall-access policy, credential activation, application writer wiring and paper execution are separate gates. The file-plan package is accepted at 100%; this staging package earns D/I/V only after local tests pass, with runtime and owner acceptance pending. Full-roadmap completion remains 12.4%, not a prediction-accuracy measure.

PostgreSQL applies authentication-file edits to subsequent Windows connections immediately, and uses the first matching rule. [PostgreSQL authentication-file documentation](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html). The replacement API can fail; metadata errors are not ignored, and the independently saved original is retained for recovery. [Microsoft file replacement documentation](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew).
