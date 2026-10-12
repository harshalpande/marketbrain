# Restricted paper writer access plan

The access diagnostic has completed successfully. The next milestone is to confine the dedicated writer to the intended database while preserving the existing application connection. This is a proposed implementation and verification plan, not permission to change PostgreSQL or Windows settings or enable LOGIN.

## Evidence and remaining decisions

E113 records the October 12 successful run: 57.98 seconds, 10 successful stages, 14 matching source files, 264 inbound rules inspected and 126 candidates retained. The container diagnostic connected read-only as `marketbrain_app`; PostgreSQL observed client/server `127.0.0.1`. Database identity matched, cleanup succeeded and the dedicated writer remained NOLOGIN. Do not repeat that unchanged diagnostic or the accepted installation/foundation checks.

Current-file HBA metadata contains six local/loopback SCRAM rules with no parse errors or withheld options. This supports the observed route, not a claim that every network path or future configuration is safe. The writer's effective ACL checks report CONNECT on other databases and TEMP on `postgres`. The report does not identify the grant source for those databases.

There are 124 candidate allow rules and two block rules; 79 allow rules show both program and service as Any in the collected fields. The collector did not retain package, interface or security-filter conditions. A PostgreSQL 11 executable also appears in one rule, but its name/path does not prove it is unused. No rule is approved for deletion or disablement based on this report.

## Proposed database restriction

Use an ordered authentication block targeting only the exact login `marketbrain_paper_review_writer`, ahead of existing general rules:

- Permit SCRAM authentication to `marketbrain` from the observed IPv4 loopback address. Include IPv6 loopback only with corresponding verification.
- Reject that login's other database connections, non-loopback sources and physical replication requests. Explicitly handle local sockets as denied for this TCP-only writer design.
- Leave all existing rules for `marketbrain_app`, administrators and other users unchanged. Keep the writer NOLOGIN while preparing/staging the block.

PostgreSQL uses the first matching HBA record; physical replication requires explicit consideration. On Windows, file changes affect subsequent connections immediately. Therefore, a live-file edit is not a harmless rehearsal. [PostgreSQL authentication rules](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html).

Do not issue blanket PUBLIC revokes. PUBLIC grants apply to every role and database defaults can include CONNECT and TEMP. A direct revoke from the writer does not cancel a remaining PUBLIC grant. The proposed HBA boundary denies connections without changing shared ACLs; effective ACL probes may still report those grants. This is connection isolation, not removal of all cross-database privileges. [PostgreSQL privileges](https://www.postgresql.org/docs/18/ddl-priv.html).

The writer must retain its reviewed non-owner permissions, no dangerous role attributes/memberships, and no CREATE/TEMP privileges in `marketbrain`. Prevent granting its identity to unrelated login roles; HBA restrictions on a login are not controls over every later SET ROLE operation. A change to these conditions blocks activation.

## Firewall scope

Keep firewall and listener settings unchanged in this plan. Before declaring the private boundary accepted, inspect the missing selectors only for rules that could apply to the actual PostgreSQL 18 listener. Include package, interface, security/IPsec conditions, active profile and executable/service identity. If a rule is genuinely broader than required, propose its exact change and rollback separately; do not clean up unrelated Windows or older PostgreSQL rules opportunistically.

The application filter has both Program and Package conditions; an Any program value alone is not an unrestricted-program verdict. [Microsoft application filters](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallapplicationfilter).

If external reachability remains unknown, keep it labelled unknown. No external scanner, LAN probe or broader network change is authorized here. TLS remains deferred under the owner-approved private single-laptop policy; a topology change reopens that decision.

## Delivery and verification sequence

| Stage | Deliver together | Completion evidence and boundary |
| --- | --- | --- |
| 1. Build and rehearse | Exact-role HBA block generator, drift detection, backup/restore workflow, targeted missing firewall selectors and one compact plan report | Offline and isolated fixtures cover rule ordering, IPv4/IPv6, non-target preservation, duplicate blocks, malformed/include layouts, partial writes, hash mismatch and recovery. No edits to the real HBA file; no LOGIN or credentials. |
| 2. Reviewed staging | Fresh target/file identity check, owner-approved exact diff, protected backup, guarded replacement and independent readback | Writer remains NOLOGIN. Existing application opens a fresh connection successfully; original non-writer HBA content is preserved. Parse errors or drift stop. No global ACL, firewall or listener edits. |
| 3. Credential and authentication proof | Reviewed credential custody/container handoff, scoped writer login tests, negative permissions and cleanup in one run | Separate authorization is required for LOGIN/credential creation. Tests run from the same application route; successful authentication alone does not wire the application or permit paper execution. |
| 4. Application review integration | Restricted writer connection, authenticated approval/rejection receipts, retry/idempotency and restart tests | Only reviewed receipt operations become eligible for activation. Cash, reservations, orders, fills, Telegram delivery and live trading remain under their separate gates. |

The first stage is the next implementation package. Firewall-selector analysis and isolated HBA tests can be prepared independently; real staging precedes credential activation, which precedes application review wiring. This groups related checks instead of requesting another general inventory run.

## Acceptance matrix for the implementation

- Correct writer, `marketbrain`, approved loopback route and correct credential: authenticated as the restricted writer after separately approved activation; expected review SELECT/function permissions only.
- Same credential against `postgres`, `template1`, another fixture database, replication, local socket or unapproved source: denied by the intended policy. Test identity/rejection cause, not just a generic connection failure or a database that already refuses connections. Use isolated fixtures for unapproved-source/replication checks; do not probe unrelated live systems.
- Wrong/expired credential, wrong database identity or unexpected role membership: stop; no fallback to the application owner/admin account.
- Existing application and administrator: fresh connections still work before and after staging, with no migration/reseed or cash changes.
- Drift, malformed configuration, interrupted write or failed post-check: retain one sanitized failure report and restore only this operation's exact protected backup when its ownership/hash guards hold; never overwrite concurrent edits. Stop for review if safe restoration cannot be established.
- Real secret: generated/entered only locally, never arguments, logs, reports or source. Explicitly design Windows DPAPI-to-container handoff; a CurrentUser blob is not assumed decryptable by a Linux container. Authentication tests close their own sessions; NOLOGIN alone does not terminate existing sessions.

Before real staging, independently compare the running cluster/database identity, configured HBA path and current file hash. Preserve encoding, ACLs, original comments and unrelated rules. Review included files and precedence; do not silently flatten or replace them. Stage only the reviewed diff under a maintenance window. Reports retain before/after hashes and stage outcomes, not passwords or full secret-bearing files.

## Progress and handoff

Access-review package: **80%**, D/I/V/R complete; findings review and owner acceptance remain pending. This is **+20 percentage points** from the last 60% checkpoint, not prediction accuracy or overall writer readiness. Full paper-first roadmap remains **12.4%**. This plan does not earn another implementation/runtime checkpoint.

This handoff only updates repository documentation. No Docker rebuild, administrator password or evidence recollection is needed. The next executable bundle will explain why it runs, what success proves, what it enables, its side effects and what remains blocked. Do not activate the writer from this plan alone.
