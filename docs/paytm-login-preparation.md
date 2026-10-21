# Paytm login preparation — synthetic only

## Scope and acceptance

2026-10-21, E139. This bounded package prepares login-state handling and a **disabled-by-default synthetic callback controller**. It does not authenticate with Paytm, exchange tokens, fetch quotes, deploy callbacks on the spare, change the VPS, or place orders. The spare handoff tests the dependency-free core; Spring HTTP behavior is verified separately by local MockMvc/context tests. Neither is a real browser/broker integration test.

Checkpoints: D10 design, I30 implementation, V20 offline verification, R20 successful spare **core** verification, A20 owner acceptance. These percentages describe this rehearsal package only, not G05, the product, prediction accuracy or profitability. Real authentication is a subsequent package.

## Evidence and current configuration

- Owner screenshot: `Market Brain Paper Data` is Active with Trading and Live broadcast subscriptions. This supersedes the older app-creation/IP-fields hold. Entitlement and API functionality remain untested; an app named Paper is not a broker sandbox.
- Registered redirect: `http://127.0.0.1:8080/paytm/callback`. Postback remains blank/disabled. Registration does not mean a handler is deployed or reachable. A loopback redirect resolves on the **browser's machine**; later login must use the spare laptop's browser.
- Both IP fields contain the purchased VPS address according to the screenshot. Registration accepted it, but actual outbound routing and secondary-IP semantics have not been proven.
- HosterDaddy SSH host-key verification is pending. No broker secret should pass through the VPS until its identity is independently verified. VPS resources are intended for a lightweight egress gateway, not application/database/model migration.
- Existing historical-data configuration is untouched. No API key, secret, request/access token, root password or private key is needed by this rehearsal.

## Official reference and unresolved contract

Pinned official SDK: [Paytm Money Python client](https://github.com/paytmmoney/pyPMClient/tree/8f966de0becc55d0feb91fdea4123c6da7d667d7).

[Constants](https://github.com/paytmmoney/pyPMClient/blob/8f966de0becc55d0feb91fdea4123c6da7d667d7/pmClient/constants.py) identify the login origin `https://login.paytmmoney.com/merchant-login`, `apiKey`/`state` fields and the separate `/accounts/v2/gettoken` endpoint. [Usage](https://github.com/paytmmoney/pyPMClient/blob/8f966de0becc55d0feb91fdea4123c6da7d667d7/README.md) describes state echo and request-token exchange. Its prose uses both `requestToken` and `request_token`; this rehearsal tests `requestToken`, **not a captured live wire contract**. Verify field names and state echo before enabling real authentication. No token-exchange client is added here.

The SDK does not prove account token lifetimes, entitlements or successful whitelisted egress. Do not infer these from synthetic tests or silently accept extra callback aliases.

## Implementation boundaries

- `PaytmLoginPreparation`: fixed HTTPS login URL construction, independent 256-bit state/browser nonces, maximum eight pending challenges, ten-minute login lifetime, bounded strict query parsing, clock-rollback rejection, expiry, restart invalidation and synchronized one-time consumption. Ten minutes is unrelated to the approved **100-second trade-review expiry**.
- Validation discards the request token; it does not retain, log, return or exchange it, or mark a user authenticated. Generic errors do not echo input; challenge `toString()` is redacted.
- `PaytmCallbackRehearsalController`: absent unless `marketbrain.paytm-auth.rehearsal.enabled=true`. No configuration/deployment script enables it. In an isolated test, POST `/paytm/rehearsal/start` requires exact loopback Host/Origin and a synthetic header. GET `/paytm/callback` accepts only the fixed fixture token and matching HttpOnly/SameSite=Lax cookie. Responses are non-cacheable and never claim authentication.
- Docker/proxy/Tailscale remote addresses and forwarded-header shortcuts are deliberately rejected. Host-to-container ingress and port mapping need separate design/testing before a real release; **do not weaken the loopback guard just to make Docker access pass**.
- No HTTP client, SQL dependency, order adapter or token vault is connected. State is lost on restart. No automatic retry or activation follows a pass.

## Spare handoff

Why: verify the spare JDK runs the exact guard and handles valid, invalid, expired and concurrent callbacks before real credentials/network dependencies are introduced.

Prerequisites: Git checkout and native JDK 21+ (`java.exe`/`javac.exe` in the same bin directory). No Docker rebuild, service restart, admin session, API key or VPS session. If needed, supply `-JavaBinDirectory 'full path to JDK bin'`; no automatic installation.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed; do not run the test.' }
& '.\ops\windows\TestPaytmLoginPreparation.ps1'
```

The runner prints progress, bounds each process, hashes sources before/after and compiles only the core/verifier into a unique temporary directory. Generated classes are removed only from that validated directory. One timestamped JSON is retained in `C:\MarketBrainData\Review`, including stage output on failure; existing evidence is never overwritten. The 38 named core checks **do not run Spring HTTP tests**; the report states this distinction.

Success: `SYNTHETIC_CORE_PASSED_REAL_AUTHENTICATION_BLOCKED`. Share that JSON only. The R checkpoint requires evidence review. Local HTTP verification uses:

```text
mvn -f marketbrain-service/pom.xml -Dtest=PaytmLoginPreparationTest,PaytmCallbackRehearsalControllerTest test
```

## Next sequential gates

1. Review spare evidence and owner acceptance. Do not rerun prior successful paper fixtures for this package.
2. Independently verify SSH host-key fingerprint; harden access with tested recovery before SSH/firewall changes.
3. Implement narrow private egress and prove **actual application-container** Paytm traffic uses the registered IPv4. Test tunnel-loss fail-closed behavior and restart recovery; preserve data collection and Telegram.
4. Prepare real callback ingress, state contract, secret custody and bounded token exchange. Prove credentials cannot leak into logs, browser storage, callback responses or evidence. Memory custody/restart behavior is separate from this discard-only handler.
5. User-driven real authentication and read-only Paytm quote checks during market hours: instrument mapping, timestamps, freshness, entitlements and rate limits.
6. Combined Telegram ACCEPT/REJECT/expiry review with fresh Paytm quotes and approved 100s/15s/0.5%/qty1/INR5,000 policy. ACCEPT records review only; no reservation, fill or broker order.

Real order execution stays deferred regardless of authentication or quote success.
