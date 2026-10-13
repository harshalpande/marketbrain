# Paper writer authentication file plan

The read-only actual-file plan is accepted (E120): the spare run completed in 23.890 seconds with all ten subprocess steps successful, zero parse errors, stable file/permission fingerprints and cleanup complete. The owner's instruction to proceed closes this bounded package at 100%. It did not edit the file or activate the writer. Next is [guarded backup and staging](paper-writer-hba-staging.md); the instructions below describe the completed read-only stage and need not be repeated now.

## Run and review

Run `ops/windows/GetPaperWriterHbaPlan.ps1` in elevated PowerShell 7 on the spare laptop. Pass the accepted `paper-writer-restriction-20261013-121046-dbd532c96a9d.json` as `PreparationReportPath`. The script pins its exact hash. Do not rerun the successful firewall comparison, installation or general access diagnostic.

Requirements: running application container, Docker CLI, native JDK21+ and `C:\Program Files\PostgreSQL\18\bin\psql.exe`. No application rebuild or restart. Confirm the database name `marketbrain`, then enter a PostgreSQL administrator username/password locally. The password is passed only in the psql child environment, not arguments, logs or saved files; application credentials remain inside its container. This does not create a writer password.

Success is `HBA_PLAN_CAPTURED_APPLY_BLOCKED`. Share the single `paper-writer-hba-plan-*.json` printed at completion. It contains source hashes, timings, phase outcomes, current identity, the proposed fixed prefix, file/ACL fingerprints and review findings. It never includes the original HBA text, its comments, administrator password or raw native errors. Failures preserve safe codes and any completed observations in the same report.

## What runs together

1. Validate accepted preparation evidence and a clean source revision.
2. Compile the existing standalone route probe into a generated temporary directory; copy only that diagnostic into the application container.
3. Query PostgreSQL in a read-only transaction with10s statement and2s lock timeouts. Pin `marketbrain`, port5432, database OID16389, cluster ID7679149914381758260 and major version18. Confirm exactly one writer role, still NOLOGIN. Read the configured HBA path, a bounded byte hash and parse-error count.
4. Open one fresh application read-only connection from the existing container. Require `marketbrain_app`, IPv4 loopback, matching database identity and server start time. It is not a writer authentication test.
5. Read the reported local `pg_hba.conf` without writing it. Reject reparse paths, unsupported encoding/layout/includes, parse errors, size above1MB, or bytes that do not match the server hash. Calculate the candidate in memory with the existing byte-preserving generator. Hash owner/group/DACL metadata; this records an ACL baseline, not tested ACL preservation during replacement.
6. Requery server/file metadata and reread local bytes/ACL. Drift blocks the plan. Remove only generated diagnostic files/directories; cleanup failure prevents success and does not hide a prior failure.

The report binds the source, current server/file/ACL identities and observed application route. It is an observation, not a lock or permanent authorization: any change requires revalidation immediately before a future apply. It does not test backup restorability, real replacement permissions, PostgreSQL parsing of the uninstalled candidate, or live rollback.

## Accepted preparation and unresolved firewall findings

E118 completed40/40 rehearsal checks and scanned264/264 current inbound rules. All126 candidate rows had the expected selector fields:124 matched saved identities, two saved IDs were absent and two current candidates were outside the baseline. The final rule metadata set was stable; the collection was not atomic. Runtime56.771s, nine matching source hashes, no configuration/database changes.

Two current allow rules have Any program/service, no package selector, and Any remote address, limited to specific local addresses and Domain/Private profiles. This is a scope-review finding, not proof of public reachability or permission to delete rules. The other saved candidates and effective network policy remain subject to review. No firewall/listener change, external probe or automatic equivalence between disappeared and current rules is included in this handoff.

## Why live staging stays separate

Windows applies authentication-file changes to subsequent connections immediately; a file edit is not a harmless preview. The next live-stage implementation must add protected backups, exact reviewed replacement, ACL preservation, independent readback/parse verification, fresh application access checks and owned-hash rollback before any real write is approved. [PostgreSQL HBA documentation](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html).

Metadata collection uses PostgreSQL's bounded binary-file read and built-in SHA256; it does not require an extension or return file contents. [Administration functions](https://www.postgresql.org/docs/18/functions-admin.html), [binary functions](https://www.postgresql.org/docs/18/functions-binarystring.html).

Writer LOGIN, credentials, application writer activation, order/fill operations and live trading remain separate later gates. TLS remains deferred under the accepted private-machine policy.

## Verification and progress

This package freezes its scope at fresh identity/route verification, read-only actual-file plan, ACL fingerprint, drift checks, safe cleanup and one report. It excludes real backup/staging/rollback and writer activation. E120 completes spare verification R20 and owner acceptance A20, bringing D/I/V/R/A to 100%. Ten source hashes match the reviewed revision when Windows checkout line endings are accounted for. PostgreSQL/Docker calls were mocked in local tests; the accepted report supplies spare-runtime evidence.

Preparation collection is100% accepted after runtime review and the owner's instruction to proceed. Full-roadmap progress remains12.4%; these package percentages are not additive and do not represent forecast accuracy.
