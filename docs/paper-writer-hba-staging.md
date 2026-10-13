# Guarded paper writer authentication staging

The accepted read-only plan verified the actual PostgreSQL file and application connection on the spare laptop. This next package backs up and applies only the fixed writer restriction prefix, then verifies new connections. It does not enable writer LOGIN, create credentials, change firewall rules, rebuild the application, or enable trades.

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

Use elevated PowerShell 7. Leave the existing application and PostgreSQL running. Do not edit PostgreSQL configuration, change permissions, restart services or run another staging/recovery command concurrently. A named mutex prevents overlapping instances of these scripts, not unrelated administrator tools.

1. Pull the committed change with a clean worktree. No Docker rebuild is needed.
2. Run `TestPaperWriterHbaStage.ps1` in a separate PowerShell process. This uses only generated temporary files and mocked services. A nonzero exit must stop the handoff before the real command.
3. Run `SetPaperWriterHbaRestriction.ps1 -ReviewedPlanPath <accepted report> -Apply`. The accepted report is `paper-writer-hba-plan-20261013-134028-6886987b4327.json`, SHA256 `C5D159FB8703627F2560BD139EF9AD00278197C52D4021B326C2C78C44B1FD64`.
4. Enter PostgreSQL administrator credentials locally, then type `APPLY WRITER RESTRICTION` only after reading the confirmation. Without `-Apply`, the script performs preflight only.
5. Share the one printed `paper-writer-hba-stage-*.json`. Do not share the private recovery directory.

Success is `HBA_RESTRICTION_STAGED_WRITER_DISABLED`. This closes file staging only after review of spare evidence. It does not resolve the effective firewall-access findings or complete the application writer.

No automatic retry or broad cleanup is performed. A stopped container produces `HBA_STAGE_APPLICATION_NOT_RUNNING`; multiple matches and malformed responses have separate errors. Drift from the accepted plan stops before replacement. Do not bypass the hash/identity checks; review changed evidence first.

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
