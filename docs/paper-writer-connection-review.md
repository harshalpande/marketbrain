# Paper writer connection security review

The permission installation is accepted in E104, and this connection inventory is now accepted in E107. Do not repeat `InstallPaperApprovalWriter.ps1 -Apply` or the accepted inventory. Both roles remain NOLOGIN; no application writer is activated. Next: [local writer foundation](paper-writer-local-foundation.md), following the owner-approved private same-machine policy with TLS deferred.

E106 corrected integer compatibility: zero exit codes accept Int32 or Int64 without coercing strings, booleans or fractions. E107 subsequently verified the collector on PowerShell 7.6.6/PostgreSQL 18: eight source matches, 16.181s total and 0.410s database stage. Findings retain SSL off, potential other-database access and the unverified application route; they do not authorize LOGIN. The command below is retained for reference, not a request to rerun.

## Scope and acceptance

One native PostgreSQL 18 read-only transaction checks the installed role/function boundaries against the saved installation plan, then reads database privilege metadata and selected authentication-file fields. A repeatable-read snapshot covers transactional catalogs, not concurrent filesystem edits. Coordinate with the administrator so configuration is not being edited during collection. The report is evidence, not a signed authorization artifact; the live permission check remains mandatory.

- Input must be the successful committed five-stage installation report, with rollback verification and all disabled-action flags intact. The target database and port come from that report; cluster identity and database OID are checked live. This is not a new installation or rollback rehearsal.
- Inventory is capped at 128 databases and 256 authentication rules, with one overflow sentinel each. Overflow/empty inventories stop without treating truncated results as complete. Catalog access uses a 15-second statement limit, three-second lock limit and 120-second process deadline; there are no account-table scans or automatic retries.
- HBA output includes rule order, connection type, database/user selectors, address/mask, authentication method and booleans for options/errors. Passwords, password verifiers, authentication option values, raw errors and configuration-file paths are excluded. The compact JSON still contains private network/role metadata; share it privately.
- A database CONNECT privilege is potential access, not a successful connection. Other-database CONNECT/TEMP/CREATE access is flagged for review; no blanket PUBLIC revoke is performed. The current writer remains NOLOGIN throughout.
- The PostgreSQL [HBA view](https://www.postgresql.org/docs/18/view-pg-hba-file-rules.html) describes current file contents, not proof of the rules last loaded or matched by an application client. Rule order and client route must be reviewed, including withheld options if present. This host-side administrator connection does not prove the Docker application's source address, authentication, TLS or database identity.
- Settings include SSL, password-encryption policy, listening addresses and port. They are observations, not end-to-end security certification. [Privilege inquiry functions](https://www.postgresql.org/docs/18/functions-info.html#FUNCTIONS-INFO-ACCESS-TABLE) inspect database ACLs without opening each database or reading its data.

No password issuance/storage, LOGIN/role/HBA edits, grant changes, configuration reload, Docker build/restart, datasource/callback activation, provider/model calls, account mutation, paper order or live order is included. Administrator credentials are prompted locally and passed only through the child-process environment, as in the accepted installer. Equally privileged OS processes can inspect that environment; use a trusted local session.

## Frozen package checkpoints

| Checkpoint | Weight | Required result |
|---|---:|---|
| D | 10% | Read-only inventory before credential activation; preserve existing grants and application state |
| I | 30% | Saved-report guard, current permission verification, bounded inventory, safe findings and one report |
| V | 20% | Offline contracts and mocked success/failure/timeout/privacy tests; no local database execution |
| R | 20% | Complete spare report with successful SQL exit and matching live identity/permissions |
| A | 20% | Review source manifest, metadata and findings; record any blockers and the scoped connection plan |

This package does not earn permission to activate the writer. Runtime authentication, credential custody and application wiring remain separate acceptance gates even if collection passes.

## Historical collector command

Use PowerShell 7 and PostgreSQL administrator credentials entered only on the spare laptop. No backup or idle application maintenance is required for this read-only check; avoid concurrent administrator configuration edits. Keep the successful installation report at its original path.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop.' }

$installationReport = 'C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json'
if (-not (Test-Path -LiteralPath $installationReport -PathType Leaf)) {
    throw 'Locate the successful installation report and correct its path. Do not rerun installation.'
}
& '.\ops\windows\GetPaperWriterConnectionReview.ps1' -InstallationReportPath $installationReport
```

Expected collection status: `CONNECTION_REVIEW_CAPTURED_LOGIN_DISABLED`. Findings are expected because custody/client-route activation is still pending; this status is not `READY_TO_ACTIVATE`. Share the single `paper-writer-connection-<timestamp>-<id>.json` printed at completion, including on failure. Native stages retain safe SQLSTATE and assertion labels; raw exceptions are withheld. No service rebuild is needed.

## Next sequence

1. Review authentication applicability and cross-database exposure from this report. Resolve a minimal writer-specific allow/reject policy if needed; never change other clients' access without a reviewed impact plan.
2. Implement local credential custody, rotation/revocation and a separately configured restricted application connection. Keep the helper NOLOGIN. Verify positive and negative authentication from the actual application route and stop safely on missing secrets or changed grants.
3. Only after that acceptance, connect controlled private Telegram/fresh-quote review with order execution disabled. Paper risk, reservations, fills/costs/P&L and the prospective pilot remain later gates.
