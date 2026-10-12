# Paper writer access review

## Why this script is needed

The foundation check passed, but PostgreSQL listens on all interfaces. We must distinguish that listening address from the access actually allowed by authentication and firewall rules. We also need an observed connection from the application container, not just its configured hostname, before preparing the restricted writer's real credential.

This is a read-only diagnostic package, not another installation or credential-storage rehearsal. TLS remains deferred for the owner-approved private, single-laptop deployment.

## What it does

1. Checks the saved successful installation and foundation reports and records source hashes/revision.
2. Reads Windows Firewall ActiveStore profile settings and enabled inbound rules whose TCP port filters could include5432. Includes Any, ranges and unknown selectors conservatively. Captures address/program/service scopes for review, not an automatic effective-access verdict. Caps filters at2000 and candidate rules at100; overflow stops rather than accepting truncated evidence. The child process has a90-second deadline.
3. Compiles a small standalone Java diagnostic with native JDK21+, copies only its class into a unique temporary directory in the running application container and runs a separate JVM there. The diagnostic uses the container's existing credentials and its bundled PostgreSQL driver. It does not expose credentials, rebuild/restart the service, register a bean or use the new writer login.
4. Opens one explicitly read-only connection to the exact `host.docker.internal` database target. Returns database name/OID, session identity, source/server addresses, port, server-start epoch and a unique diagnostic application name. JDBC timeouts bound the query; a45-second JVM watchdog bounds the diagnostic. The transaction is rolled back. No account data or SQL query text is collected.
5. Prompts locally for PostgreSQL administrator credentials, rechecks that the installed writer remains NOLOGIN/restricted and reads current HBA metadata. Compares database name/OID, port and server-start epoch with the container probe. A mismatch stops. This is operational instance correlation, not cryptographic server authentication or proof of the application's existing pooled sessions.
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

Local verification:719 Java tests, including11 new probe tests;62 access/firewall contract assertions;139 mocked full-runner assertions. Standalone `javac --release 21` emits exactly the one class used by the runner. Actual container execution, Windows firewall semantics and PostgreSQL reads remain spare checks, not local test claims.

Primary references: [PostgreSQL HBA rules](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html) (first matching record; Windows changes apply to subsequent new connections), [Windows firewall rules](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallrule) and [firewall profiles](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile). Metadata collection does not replace an effective network-access assessment.
