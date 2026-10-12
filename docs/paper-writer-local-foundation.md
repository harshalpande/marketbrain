# Local paper writer foundation

The owner-approved deployment policy is one private, owner-controlled laptop. **TLS is deferred**, not a prerequisite for the next paper-integration milestone. Keep database and portal access private, use the restricted review writer, and keep secrets out of source control and evidence. This package prepares connector and credential-storage candidates and collects local boundary observations. It does not enable the writer or create transactions.

## Accepted connection review

E107 accepts `paper-writer-connection-20261012-154834-0deecf1e5921.json`: successful read-only collection on PowerShell 7.6.6, eight source matches, 16.181 seconds total and 0.410 seconds database time. NOLOGIN and all disabled-action flags remain intact. Do not repeat the accepted permission installation or connection inventory.

The report observes SSL off, SCRAM authentication rules and potential CONNECT privileges on other databases, with TEMP on `postgres`. These are not successful writer logins. A wildcard listener does not establish public exposure; effective authentication, firewall and routing still matter. The next local observations are collected with synthetic custody checks, without another administrator login.

## Implemented candidate

- `PaperWriterConnector` implements the restricted-review connection interface, but is not a Spring bean, application datasource or background worker. Its activation guard stops before reading secrets or dialing. No application properties, Compose environment or server configuration changes.
- Explicit `PRIVATE_SAME_MACHINE` accepts only `localhost`, `127.0.0.1` or `host.docker.internal`, uses no TLS and needs no certificate. This host allowlist is a configuration guard, not proof of routing or confidentiality. Docker container loopback is not the Windows host. Actual source/destination and private access require review before activation.
- Optional `VERIFIED_TLS` remains available for a later topology; it requires certificate verification and never automatically falls back to plaintext. This handoff does not configure it.
- The fixed writer username cannot be replaced by an owner/admin identity. Each connection checks session/current role, database name/OID, dangerous role attributes and role membership before returning. The metadata query timeout is 5 seconds; connect timeout is 10 seconds and login/socket timeouts are 15 seconds. No account-table scan. This does not re-certify every installed grant or cryptographically authenticate a server under the private policy.
- Fresh caller-owned secret buffers and connection properties are cleared; raw driver/secret exceptions are withheld. JDBC/JVM immutable password copies cannot be reliably erased by this code.
- Windows custody uses DPAPI CurrentUser, private ACLs, purpose binding, bounded reads, non-overwriting creation and reparse-path rejection. The runner uses only a random synthetic value in its own fixture. Existing approval keys and real credentials are untouched. Moving a protected blob to another Windows identity/machine is not a supported recovery procedure. Real rotation/revocation, Docker handoff and backup recovery remain separate work.

## Spare verification

Use PowerShell 7 as the usual owner account, with Docker Desktop and the existing service/UI containers running. No administrator password, rebuild, restart or model run is required.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Preserve/review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop.' }
& '.\ops\windows\TestPaperWriterFoundation.ps1' -InspectLocalBoundary
```

The script performs fifteen synthetic custody checks and selectively inspects both containers' published ports, a fixed classification of the service's configured database URL, and Windows listeners on port 5432. It never prints that URL, passwords or the full container environment. Docker stages have a 15-second process deadline and no retry. Multiple matching containers stop as ambiguous rather than choosing one. Successful synthetic fixture files are removed, never application files.

Share only `paper-writer-foundation-<timestamp>-<id>.json`. Expected collection status: `FOUNDATION_CAPTURED_PRIVATE_BOUNDARY_REVIEW_REQUIRED`, with 15 custody checks. Findings may still require action. This is deliberately not `READY_TO_ACTIVATE`: configured-route and port metadata cannot prove a database session, firewall policy or external reachability. The handoff requires `-InspectLocalBoundary`; without it, synthetic custody alone cannot satisfy spare acceptance.

## Checkpoints and next release

Frozen scope: offline connector contracts, synthetic Windows custody, combined local-boundary inspection and one report. D10/I30/V20/R20/A20 gives **60%** after local verification. R requires 15 custody checks and complete spare boundary collection with matching sources. A requires review of findings and identification of remaining activation conditions. Neither grants writer LOGIN or completes application integration. Connection inventory is separately **100%**; full paper-first roadmap remains **12.4%**.

After the report, implement the smallest route/access correction if needed and the real credential handoff/revocation path. Then perform separately authorized writer login and positive/negative checks from the application route: exact target/role, review receipt persistence, duplicate handling and rejection of cash/order/secret operations. Wire private Telegram and fresh-quote review after acceptance. Paper fills, reservations and P&L follow their own policy tests. TLS stays deferred unless topology or trust boundaries change.

## Technical references

- [PostgreSQL JDBC properties](https://jdbc.postgresql.org/documentation/use/): explicit transport policy and timeouts.
- [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/): loopback bindings and network exposure considerations; not a firewall audit.
- [Windows ProtectedData](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata): CurrentUser protection is not protection against a compromised owner/admin session.
