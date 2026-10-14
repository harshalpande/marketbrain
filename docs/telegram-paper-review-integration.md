# Telegram first paper review integration

**Accepted E129, 2026-10-14:** spare verification passed all 18 checks in 250.791 seconds; all 40 source hashes match the Windows checkout, test resources were cleaned up and the owner accepted this bounded milestone. Package 100%; real writer activation and Telegram round trip remain pending. Do not rerun the isolated bundle. Current handoff: [protected writer credential staging](paper-writer-credential-staging.md).

2026-10-14. Phone interaction is **Telegram only**: receive a BUY/SELL proposal, ACCEPT or REJECT it, and receive its outcome. HOLD has no execution button. The portal is for laptop account/history/report review; smartphone portal access is not a release gate. Tailscale is not a dependency of the outbound Telegram polling path. Its removal is a separate, reversible dependency-review task; this package does not stop or uninstall it or change firewall rules.

## This milestone

Connect the existing private callback adapter to the dedicated restricted writer through default-off Spring configuration, then verify that connection in a disposable PostgreSQL fixture. This closes a source-wiring gap without activating production credentials, publishing proposals or enabling paper execution. It does **not** complete the real Telegram round trip.

- Normal application configuration remains unchanged. `marketbrain.paper.review.enabled` defaults to false; no new callback, credential read, connection or HTTP client is created while disabled.
- Explicit opt-in requires PAPER mode, configured Telegram and Upstox, `activation=REVIEW_ONLY`, `transport=PRIVATE_SAME_MACHINE`, exact writer host/port/database/OID, an absolute credential-file path, and a complete versioned review policy. No risk thresholds or credentials are silently supplied. Invalid opt-in configuration fails startup before polling; ordinary deployments with this feature disabled are unaffected.
- The credential file contains a separate 256-bit hex writer password, not the approval encryption key. Bounded reads, fresh buffers and sanitized errors are implemented. The connector checks the fixed non-owner role and target identity and has connection/query deadlines. There is no fallback to the main datasource. Real DPAPI custody, mount permissions, issuance, revocation and application-route proof remain deployment gates; this script provisions none of them.
- Only instrument-key lookup uses the existing application datasource, through the existing bounded read-only adapter. Review writes use only the restricted connector and installed review functions. The existing Upstox quote adapter is connected only inside the opt-in callback path; REJECT and terminal receipt replay do not fetch quotes.
- Existing private-user checks and `mbp:` tokens remain authoritative. ACCEPT requests quote/account/policy review; `ACCEPTED_EXECUTION_BLOCKED` is not an order. Missing quotes produce a blocked review, not invented acceptance. No publisher, dispatch worker, order API, reservation, fill or ledger writer is registered here.

The conditional bean follows [Spring Boot property conditions](https://docs.spring.io/spring-boot/3.5/api/java/org/springframework/boot/autoconfigure/condition/ConditionalOnProperty.html). The phone needs only Telegram and Internet; the laptop polls [Telegram getUpdates](https://core.telegram.org/bots/api#getupdates), without an inbound webhook or phone-to-database route.

## Combined verification

The new `-TelegramReview` bundle builds a verification image, executes the Spring configuration/polling contracts during that build, then runs **15 preparation + 3 post-restart database scenarios**. It uses a uniquely labelled internal-only network and disposable PostgreSQL 18 container, no published ports, host mounts or application configuration. Both verifier processes join only that owned fixture's network namespace so the real connector uses loopback without widening its host allowlist. The database image identity is recorded.

TCP authentication is explicitly SCRAM; otherwise the official container's default localhost trust could hide a bad password. See the [official PostgreSQL image authentication and initialization documentation](https://github.com/docker-library/docs/blob/master/postgres/README.md). Local Unix-socket trust is confined to the disposable database container for its initialization/readiness commands; it is not an application HBA change.

| Group | Evidence required |
|---|---|
| Wiring and configuration | Disabled-by-default, all opt-in fields required, private target, no owner-datasource fallback, no execution bean |
| Callback processing | ACCEPT, REJECT, duplicate/opposing clicks, wrong identity, malformed/group callbacks, expiry and unavailable quotes |
| Actual fixture authentication | Correct secret succeeds, changed secret fails, NOLOGIN revokes new connections, unsafe role attributes fail |
| Permissions | Cash/order writes, delivery/key reads, temporary DDL and helper-role escalation denied |
| Durability | Concurrent clicks produce one receipt; fresh JVM after PostgreSQL restart reuses the saved receipt and handles a new rejection |
| Accounting | INR100,000 cash preserved, zero reserves, zero ledger revisions, orders and fills |

Polling tests use the actual handler/poller with transport/store doubles to verify that database failure does not advance the cursor or acknowledge a callback. A fresh worker retries from the saved cursor. This is not a successful live Telegram callback; actual API acknowledgements, outages and delivery reconciliation still need spare acceptance. Database scenarios invoke the real callback/connector against PostgreSQL but use synthetic quotes and identities, with zero Telegram/provider/model calls.

Each stage has a timeout and ten-second heartbeat. Build default limit is 900 seconds, fixture image pull 300, preparation 300 and recovery 120; cleanup can add time. Allow several minutes, potentially longer for first image/dependency downloads. Do not promise a runtime from offline tests. Only this run's labelled successful fixtures and anonymous volumes are removed. Failed fixtures are retained with stop requested; built images and one shareable report remain. No application restart, administrator password, HBA reapply or real credential is needed.

## Spare laptop command

Use PowerShell 7 as the normal owner with Docker Desktop running in Linux-container mode. Keep existing MarketBrain services running. This builds only the verifier, not the application service.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) { throw 'Preserve and review local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; stop.' }
& '.\ops\windows\TestPaperPersistenceBundle.ps1' -TelegramReview
```

Share only `C:\MarketBrainData\Review\paper-telegram-<timestamp>-<id>.json`, including if it fails. Expected status is `ISOLATED_TELEGRAM_WIRING_PASSED_ACTIVATION_PENDING`; the report must contain all 18 named scenarios, zero failed checks, unchanged money counters, `applicationWriterActivated=false` and `realTelegramVerified=false`.

## Progress and what follows

Frozen package scope is default-off wiring, bounded credential-file reader, Spring/polling tests, combined isolated authentication/callback/restart verification and this one-file handoff. D10/I30/V20/R20/A20 applies only to this package. Local verification can earn 60%; R requires the spare report, and A requires review/owner acceptance. Full-roadmap progress is not recomputed from this small package; predictive accuracy remains unmeasured.

After acceptance, the remaining sequence is:

1. Complete real writer credential custody/rotation/revocation, verify fresh authentication and denied privileges from the application route, and explicitly approve review-policy limits. Keep the helper NOLOGIN and never grant money writes to the review writer. No additional smartphone-portal test is needed. Targeted network collection is already captured; do not repeat broad firewall enumeration.
2. Controlled real private Telegram publication and callback receipt test, with execution disabled. The new configuration alone cannot publish a test proposal; publisher permissions and durable delivery/reconciliation must be wired and verified. A callback acknowledgement popup is not yet a durable outcome-notification workflow.
3. Separately integrate fresh-quote/risk revalidation with atomic paper reservations, fills, fees, holdings and P&L. Only paper funds are in scope. Real Paytm orders and predictor promotion remain separate release gates.

The open network-policy finding is retained: two broad Tailscale-interface allow rules were mapped, but external reachability and VPN ACLs were not proven. Removing Tailscale, if later authorized, does not itself certify all database exposure. This does not prevent isolated engineering work and does not make the phone portal a prerequisite.
