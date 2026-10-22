# Paytm main-application route and restart verification

**Accepted update, E157 (2026-10-22):** owner run223cdc084de64c90a80c527032ac6879 passed8/8 stages in456.253s, including real main-process restart locking and account preservation. [Evidence](evidence/paytm-application-route-spare-20261022.json). Do not repeat the deployment below: next is the [read-only operations snapshot](paytm-operations-review.md). Earlier pending wording is retained as package history; authentication/quotes/operational acceptance are still open.

2026-10-22, E155/E156. Owner container probe accepted 7/7 stages in 137.68 seconds; temporary probe cleanup and unchanged app artifact confirmed. It was not the running Spring process. This package is the next portion of integration gate 2, not completion of all operational gates or broker authentication.

## Implementation and authority

`PaytmApplicationRoute` is a component inside the normal application JVM. It uses the accepted `PaytmGatewayTransport` with fixed `host.docker.internal:18889`, fixed HTTPS root HEAD, normal certificate/hostname checks and no direct fallback or redirect. No global HTTP configuration, Upstox, Telegram, schema or Compose changes. Java's [explicit proxy and redirect controls](https://docs.oracle.com/en/java/javase/21/docs/api/java.net.http/java/net/http/HttpClient.Builder.html) underpin the transport; the existing direct historical RestClient is deliberately retired, not silently reused.

Startup is LOCKED. The explicit diagnostic arm grants only four credential-free HEAD requests for at most 20 monotonic minutes. Transport failure locks it; recovery requires explicit rearm. Startup/restart never restores the lease. Synchronization serializes checks and state changes; request deadline remains 15 seconds. No credential, history POST, quote request, order, cash reservation or writer unlock is possible. Historical calls return NOT_CONFIGURED when disabled, otherwise AUTHENTICATION_AND_DATA_INTEGRATION_PENDING without contacting a provider, even with a configured legacy token.

POST `/api/v1/paytm/route/{status,arm,head,lock}` requires PAPER mode, the existing paper-read token and `X-MarketBrain-Paytm-Route: credential-free`. This is diagnostic read authority, not execution authority. Empty/malformed tokens, browser Origin, forwarded headers, wrong Host, query/body/transfer-encoding and unknown commands are rejected. Responses are no-store. The runner requires Docker's localhost-only 8080 publication; this controller does not infer client identity from Docker source IP. The transport can arm only with Paytm enabled=false and an empty access token. No secrets are accepted in the diagnostic body or stored in its report.

## Guarded deployment and one report

Run only on the spare in PowerShell 7. Existing accepted three-file Compose stack (`compose.yaml`, `compose.paper-storage.yaml`, `compose.paper-review-memory.yaml`) is required, with the paper writer LOCKED. A different stack/configuration stops for review. No guessing of containers or replacement of keys.

The runner validates the accepted container evidence, local Docker endpoint, clean Git checkout, unchanged migration sources and current paper account. Private Docker inspect/config is processed in memory, never captured as shared subprocess output. The existing MARKETBRAIN environment is preserved and compared against the resolved Compose plan, as are storage mounts, loopback ports, review policy and network. Broker access must remain disabled. No administrator database credentials are requested.

After the owner confirms idle jobs and `DEPLOY_PAYTM_ROUTE`, it builds a uniquely named image (up to 30 minutes, heartbeat every 10 seconds). The old service keeps running during build. It then recreates only the application service, verifies health and identical paper account/ledger, verifies the new endpoint rejects missing auth and starts locked, and begins the familiar bounded tunnel window. Daily alerts pause briefly during recreation/restart. Builds/images are retained, never pruned. On deployment/health failure it stops with evidence; no automatic rollback, retry or credential unlock. The prior image/container IDs and safe failing phase are recorded for reviewed recovery. Do not run ad-hoc Compose commands against the retained images.

The four network cases run against HTTP in the actual Spring process: gateway available, tunnel closed, reconnected, VPS proxy stopped. Failure cases require a transport failure and LOCKED state, then a second HEAD must be locally blocked. After stopping the proxy, arm without a network call and restart the service once: the new boot UUID must differ and both diagnostic route and paper writer must be LOCKED. Final explicit lock and paper-account reconciliation are mandatory. Report retains phase timings, safe results, current-run server report and all four checks in one JSON; it does not claim to freeze ongoing historical-market-data writes.

Expected success: `APPLICATION_ROUTE_PASSED_AUTHENTICATION_AND_OPERATIONS_PENDING`, eight stages, four application route checks, fresh startup/restart locks, final lock, unchanged paper account and tunnel cleanup. `applicationProcessVerified=true` then refers to diagnostic route wiring only. Root HTTP503 is a TLS transport pass but not authenticated endpoint health. No credentials or broker calls beyond HEAD.

## Complete handoff

1. Fresh administrator PuTTY session; `whoami`, `sudo whoami`, and:

```bash
sudo systemctl show marketbrain-paytm-gateway.service -p ActiveState --value
sudo ss -H -ltn 'sport = :18888'
sudo systemctl list-timers --all 'marketbrain-tunnel-stop-*' --no-pager
```

Require inactive, no listener and no pending test timer. Keep recovery access. No gateway installer rerun.

2. On spare PowerShell 7 with Docker and MarketBrain running:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
$accepted = 'C:\MarketBrainData\Review\paytm-container-route-20261022-171235-79e1a66d722c44c0ad9e8c3fcbf4b4d7.json'
if (-not (Test-Path -LiteralPath $accepted -PathType Leaf)) { throw 'Accepted container report missing.' }
& '.\ops\windows\TestPaytmApplicationRoute.ps1' -ContainerEvidencePath $accepted
```

3. Confirm `DEPLOY_PAYTM_ROUTE` only with jobs idle; allow build and health checks. At ADMIN-VERIFIED confirm fresh admin/sudo access; load the separate gateway PPK in Pageant and confirm KEY-READY. Never send keys/passphrases/tokens in chat.
4. When PowerShell copies the command, manually type `sudo -v` in PuTTY, then paste the clipboard command. Type START-TEST at its prompt. Copy only the newly printed SERVER_READY line into PowerShell. Surrounding whitespace is now accepted; up to three attempts are allowed, but a different/stale run ID is never accepted. Only validation outcome/attempt count is saved, not arbitrary pasted text.
5. Wait for the combined network checks. Type STOP in PuTTY only when PowerShell asks. Copy BEGIN_SERVER_REPORT through END_SERVER_REPORT, return to PowerShell and press Enter. Do not enter START-TEST/STOP at a normal shell prompt.
6. Let the main application restart verification and final checks finish. Remove only the gateway key from Pageant when asked; confirm KEY-REMOVED. Share the single `paytm-application-route-...json`. Complete cleanup prompts even after failure; do not rerun blindly or expose ports.

## Verification and remaining gates

Local: 10 new JUnit tests (24 Paytm tests total), real Spring bean construction/new-context locks, MockMvc auth/input controls, existing 18 native proxy assertions, 28 mocked whole runner cases, 10 real deployment-control-flow cases with mocked Docker/HTTP (including configuration drift, cancellation, writer unlocked, build/deploy/health/account/restart/final-lock failures). No actual Docker deployment is claimed locally.

Fresh public-egress observation, long-running gateway/key custody and OS maintenance remain explicitly pending. The temporary Pageant key and 20-minute server window are not an unattended design. Review these alongside this report before login activation. Then real callback/token lifecycle, quotes and combined Telegram review follow; live orders are not a prerequisite for returning to paper development. The prior 4-6 test-round estimate was an allowance, not guaranteed completion; no whole-project percentage is inferred from this bundle.
