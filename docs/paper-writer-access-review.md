# Paper writer access review

**Current result:** E113 collected access metadata successfully and E125 subsequently verified the real HBA restriction, with the writer still NOLOGIN. This access-review package remains **80%** because policy findings and acceptance are separate from successful staging. Next: [targeted network mapping of two saved rules](paper-writer-network-review.md) (E126). Do not rerun this general diagnostic or HBA Apply; commands and failed-run history below are retained for reference.

## Why this script is needed

The foundation check passed, but PostgreSQL listens on all interfaces. We must distinguish that listening address from the access actually allowed by authentication and firewall rules. We also need an observed connection from the application container, not just its configured hostname, before preparing the restricted writer's real credential.

This is a read-only diagnostic package, not another installation or credential-storage rehearsal. TLS remains deferred for the owner-approved private, single-laptop deployment.

## What it does

1. Checks the saved successful installation and foundation reports and records source hashes/revision.
2. Reads Windows Firewall ActiveStore profile settings and retrieves enabled inbound rules directly. Inspects each rule's associated port filter; only possible TCP 5432 matches need address/program/service queries. Includes Any, ranges and unknown selectors conservatively. Limits: 2,000 enabled inbound rules, 1,000 candidate rules, approximately 1 MiB per checkpoint, 180-second cooperative deadline and 210-second outer process timeout. Overflow stops rather than accepting incomplete evidence. Checkpoints after profiles and every 100 scanned rules preserve the last complete snapshot if the process is interrupted; ordinary failures preserve all collected rows. Checkpoints are embedded in the one final report, not separate files. No rule settings change.
3. Compiles a small standalone Java diagnostic with native JDK21+, copies only its class into a unique temporary directory in the running application container and runs a separate JVM there. The diagnostic uses the container's existing credentials and its bundled PostgreSQL driver. It does not expose credentials, rebuild/restart the service, register a bean or use the new writer login.
4. Opens one explicitly read-only connection to the exact `host.docker.internal` database target. Returns database name/OID, session identity, source/server addresses, port, server-start epoch and a unique diagnostic application name. SQL uses `host(inet_client_addr())` and `host(inet_server_addr())` rather than `inet::text`, which includes a mask. The validator also accepts full IPv4 `/32` and IPv6 `/128` host masks from older diagnostics, preserving raw values; it rejects subnets, mismatched masks, hostnames and malformed addresses. Loopback findings use parsed addresses, including IPv4-mapped IPv6. JDBC timeouts bound the query; a45-second JVM watchdog bounds the diagnostic. The transaction is rolled back. No account data or SQL query text is collected.
5. Prompts locally for PostgreSQL administrator credentials, rechecks that the installed writer remains NOLOGIN/restricted and reads current HBA metadata. Compares database name/OID, port and server-start epoch with the container probe. A mismatch stops. Validated receipt/inventory metadata is checkpointed before route comparison, and `validationStage` identifies any later failing check. This is operational instance correlation, not cryptographic server authentication or proof of the application's existing pooled sessions.
6. Removes only its exact temporary diagnostic class/directories and writes one compact JSON. No recursive deletion, application-file replacement or broad cleanup. A cleanup failure is recorded separately from the original error; no automatic retry.

Each process has a deadline. The administrator metadata stage retains the existing15-second statement,3-second lock and120-second outer process limits. Git/source checks and compilation run locally on the spare laptop. Native JDK21+ and the current application image layout (`/app/app.jar` with a bundled PostgreSQL JDBC jar) are prerequisites; unsupported layouts stop without installing tools or changing the application.

## What success proves and enables

Expected collection status: `ACCESS_EVIDENCE_CAPTURED_REVIEW_REQUIRED`. It proves the diagnostic could observe a read-only application-container route, correlate it with the inspected database and collect untruncated access metadata. It does **not** prove external reachability is impossible, certify every firewall predicate, or enable LOGIN. Proxy/VPN/NAT forwarding, third-party firewalls and packet-level reachability are not tested. HBA rule order and complex selectors must be reviewed rather than inferred from one address.

If findings are satisfactory, prepare real writer credential custody/handoff and the smallest writer-specific cross-database restriction. If access rules are broader than intended, propose a scoped correction first. No blanket PUBLIC revokes or automatic firewall/HBA edits. Positive/negative writer authentication and application review persistence follow separately; Telegram review and paper execution remain later gates.

## Run on the spare laptop

Use **PowerShell7, Run as Administrator**, under the same Windows account that runs Docker Desktop. Windows elevation is for firewall inspection; the PostgreSQL administrator username/password are separate and prompted locally. Keep the existing service running and avoid concurrent database/firewall configuration changes. No Docker rebuild, model run or writer reinstallation is needed.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop.' }
$parameters = @{
    InstallationReportPath = 'C:\MarketBrainData\Review\paper-writer-install-20261012-151121-ca9707876fe9.json'
    FoundationReportPath   = 'C:\MarketBrainData\Review\paper-writer-foundation-20261012-174139-065c90530aef.json'
}
foreach ($file in $parameters.Values) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Locate the existing successful report and correct its path: $file"
    }
}
& '.\ops\windows\GetPaperWriterAccessReview.ps1' @parameters
```

Share the one `paper-writer-access-<timestamp>-<id>.json` printed at completion, including on failure. It contains private network and rule metadata; share privately. Passwords, password verifiers, full container environment and raw native exception text are excluded. Do not rerun an installer if this diagnostic fails.

## Scope and evidence checkpoints

Frozen package: saved prerequisites, bounded firewall/HBA collection, same-container read-only diagnostic, instance correlation, temporary-file cleanup, one report and safe failure evidence. D10/I30/V20/R20/A20: **60%** after offline verification; R requires complete spare output with matching sources and successful cleanup; A requires review of route/access findings and recording any prerequisites to credential preparation. No login/application/execution authority follows from completing this package. Full roadmap stays12.4%.

Current E112 verification: 720 Java tests, 186 access/firewall assertions and 216 mocked full-runner assertions passed. Tests cover PostgreSQL host-mask output for both client/server, IPv4/IPv6/mapped loopback classification, rejected subnet/malformed addresses, and retained admin evidence on validation failure, in addition to the previous collector limits/timeouts. The actual failing report's two address values reproduce the old rejection and pass the corrected parser. Real firewall/database runtime is still spare-only.

The latest October 12 report records successful firewall collection (264 inbound rules, 126 candidates, 31.03s), diagnostic compilation, application read-only query, administrator query and cleanup. It stopped at `ACCESS_ROUTE_ADDRESS_INVALID` after 66.08s because both addresses were `127.0.0.1/32`. This supersedes the earlier E111 collector-limit failure; it is not an administrator/password failure. The repair adds no completion credit: access review remains 60%, with end-to-end spare verification and findings review pending. Retry only this diagnostic after pulling; keep installation and foundation evidence unchanged.

Address-format reference: PostgreSQL documents that an explicit `inet` to `text` conversion includes the netmask, while [`host(inet)` returns only the address](https://www.postgresql.org/docs/18/functions-net.html). The correction changes representation, not authentication or access policy.

Primary references: [PostgreSQL HBA rules](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html) (first matching record; Windows changes apply to subsequent new connections), [Windows firewall rules](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallrule), [associated port filters](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallportfilter) and [firewall profiles](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile). The collector uses documented rule filters and associated objects, not guessed identity joins. Metadata collection does not replace an effective network-access assessment.
