# Supervised paper workflow: 20 November 2026 scope decision

The owner has explicitly prioritized a working supervised paper application over
unattended clock reliability. VPS UTC is accepted as the reference for this
prototype. Windows NTP synchronization, laptop/VPS offset screens, collector
publication and G3 lifecycle completion are not prerequisites for this path.
This is a scope decision, not evidence that deferred tests passed.

## Delivery sequence and acceptance

| Milestone | Current state | Runtime acceptance |
| --- | --- | --- |
| Supervised login and protected account read | Accepted on spare: login/read and cleanup, 110.105 seconds | Owner login, one-use callback, read token exchange and account-read HTTP response |
| Real quotes | Three stale samples captured on spare; mapped/fresh run pending | Verified instrument mapping, actual provider timestamp and price; missing/stale quote rejection |
| Combined Telegram actions | Pending | ACCEPT, REJECT, 100-second expiry and duplicate rejection in one batch |
| Paper execution and portal | Pending integration | Virtual cash/holdings, costs, fills and portal reconciliation |
| Unattended lifecycle and clock reliability | Deferred | Resume after supervised workflow works |

The original accepted checkpoint score remains G1 100%, G2 100%, G3 80%,
G4 60%, G5/G6 0% (17/30 accepted, 56.7%). G4.1, G4.2 and G4.4 accepted by the collected owner-login report. Callback negative and lifecycle runtime cases remain open. New code is not runtime acceptance. There is no
claim of prediction accuracy, complete paper integration or live-order readiness.

## Quote probe (21 November)

`StartPaytmSupervisedLogin.ps1 -TestQuotes -QuoteSymbol RELIANCE` reads three LTP samples, five seconds
apart, before locking the same authenticated session. The default is the
provider documentation's NSE EQUITY security ID 3456. This is a protocol probe,
not a verified company mapping; it must not feed proposals or execution.
An explicit `-QuoteSecurityId` can select another positive provider ID.

The endpoint uses only the in-memory read token and the existing fixed proxy.
Java permits at most three calls per session, spaced at least five seconds
apart. HTTP errors end the session without automatic retry. Missing packets
are recorded as NO_QUOTE; malformed, future or missing timestamps require review.
Stale packets are retained as diagnostic evidence but never marked fresh.
Fresh means age between zero and 15 seconds against the VPS-anchored clock at
receipt. This does not prove market-open status, symbol mapping or execution
eligibility. Weekend/closed-market data can complete capture while freshness
remains pending. No laptop-clock repair is required for this workflow.

Contract sources checked 21 November: [official live-data documentation](https://developer.paytmmoney.com/docs/api/live-market-data-api)
for the LTP response and read-token support; [official SDK epoch converter](https://github.com/paytmmoney/pyPMClient/blob/master/pmClient/epochConverterUtil.py)
for seconds since 1980 (add 315532800 for Unix seconds). Raw provider seconds,
converted time, VPS observation, age, price and status are recorded in one compact
report. Unknown provider fields and all credentials are excluded from queue
collection. Full instrument-master mapping and real market-hours acceptance
remain G5 work. The public master download succeeded on the controller on 21 November; its schema and selected rows are recorded in the mapping preparation evidence.

## Login implementation

`compose.paytm-supervised.yaml` opts the main application into PAPER-only login.
It cannot run alongside the synthetic rehearsal controller. The existing paper
read token authorizes local start/status/lock calls. The Docker port remains
published on Windows loopback; do not expose this HTTP surface externally.

The launcher starts the existing disabled gateway task, reads the current VPS
clock through the pinned SSH clock-reader account, and submits that anchor plus
app credentials locally. The VPS NTP flag is recorded, not used as an acceptance
gate. Java advances the anchor using `System.nanoTime()` for a 20-minute session.
Callback expiry is 10 minutes. No host wall-clock comparison is performed.
TLS certificate validation still uses the platform trust stack; grossly wrong
system dates can affect TLS independently of application time policy.

Owner authentication and OTP occur on Paytm's browser page. The callback binds
one random state to an HttpOnly SameSite cookie and consumes the token once.
Token exchange and a single account-details GET go through the fixed VPS proxy.
Only `read_access_token` is retained in application memory. Trading/public
tokens are discarded, no direct route or redirects are permitted, and no order
endpoint exists in this client. Provider responses are size bounded and raw
account data, credentials and callback URLs are excluded from reports.

Success means token exchange plus a non-empty, non-error JSON HTTP 200 account
read response. It does not verify account identity/holdings, quote entitlement,
market freshness or order capability. No provider-side logout is performed:
local lock discards references to credentials/tokens; it does not revoke tokens
at Paytm. Restart requires login again. Java cannot promise secure erasure of
immutable strings from heap memory.

The launcher polls with progress, locks the application and stops/disables its
gateway on completion or caught failure. It saves one compact JSON including
stage, sanitized provider failure and cleanup outcome. If the terminal is killed,
the gateway may remain running; the application's elapsed session still expires.
This is supervised operation, not crash/restart lifecycle acceptance.

## Run on the spare laptop

In elevated PowerShell 7, from the existing repository:

```powershell
$ErrorActionPreference = 'Stop'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\DeployPaytmSupervised.ps1
& .\ops\windows\StartPaytmSupervisedLogin.ps1 -TestQuotes -QuoteSymbol RELIANCE
```

The deployer retains the current Compose project/overrides, builds before
replacing the application and waits for health. The launcher requests the paper
read token, developer API key/secret and encrypted OpenSSH **clock** key path.
These stay on the spare laptop. Supply the clock-key passphrase only in the
native SSH prompt and complete the browser login there. No PuTTY copying is
needed. The gateway and collector must initially be stopped/disabled; existing
failure markers are preserved rather than silently reset.

Deployment correction (20 November): Compose overlays rely on process-only
variables from earlier guarded deployment. The deployer now reconstructs those
from the existing container environment and mounts, including approval-key host
file, review directory, database OID and a new candidate image tag. It compares
the resolved Compose settings privately before building, restores temporary
process variables in `finally`, and checks applied environment/mounts afterward.
It never reads or regenerates the approval-key contents. The old image remains
available. A separate `paytm-supervised-deployment-<id>.json` is now saved even
when configuration/build fails; the same queue collector can fetch it. Local
regression coverage includes actual Compose interpolation using fixture values;
the subsequent spare deployment and login/read have now passed (21 November).

Expected success: `SUPERVISED_LOGIN_READ_PASSED_QUOTES_PENDING` with application
locked and gateway stopped/disabled. A provider error is evidence to inspect,
not a reason to rerun old clock reliability tests.

The controller can retrieve the result using the existing `paytm-denial-recovery`
job kind, `Observe` mode, pinned to this implementation's pushed revision. The
new artifact is **read-only collection**, not a gateway mutation. Rebuild/check
it with `ops/automation/Build-SupervisedReportJob.ps1`; historical recovery
artifacts remain available at their immutable revisions. Collection success
does not automatically accept the contained test result.

## Provider contract checked

Checked 20 November 2026 against Paytm's official SDK:
[authentication body and response](https://github.com/paytmmoney/pyPMClient/blob/master/pmClient/pmClient.py),
[fixed route definitions](https://github.com/paytmmoney/pyPMClient/blob/master/pmClient/constants.py),
[read-token header](https://github.com/paytmmoney/pyPMClient/blob/master/pmClient/apiService.py).
Runtime provider acceptance remains pending.

## Callback correction, 21 November 2026

The owner's actual redirect contained `success=true`, `requestToken` and `state`.
The original parser only accepted two fields, so it rejected this callback
before token exchange. It now accepts the optional exact `success=true` value;
false/empty/other values, unknown fields and duplicate (including encoded)
names remain rejected. Matching browser binding, state, expiry and one-use
consumption are still mandatory. A rejected callback carrying the current
owner's cookie closes the attempt and exposes a sanitized failure to polling.
Unrelated cookie values cannot cancel the active attempt. Starting again clears
the prior failure and creates new state/binding values.

The launcher now saves stage and application-state checkpoints during the run
with atomic replacement; the queue reader permits replacement while reading.
This avoids returning only the initial PREPARATION checkpoint while the browser
and terminal are already at LOGIN. No callback query/token is saved in reports.
Close old callback tabs and use the new browser launch on retry.

Local verification (21 November): 44 Java tests passed with zero failures/errors;
PowerShell handoff parsing/artifact equality and quote/login collection fixtures
passed. Actual quote entitlement/freshness is not yet accepted.

## Next combined run: mapped quotes

The new QuoteSymbol option downloads the fixed public equity master (25 seconds,
4 MiB maximum, no credentials or redirects), requires one NSE/EQ/E/ES row and a
unique NSE security ID, and records the source hash and selected symbol. It runs
before starting the gateway or prompting for credentials. A download or mapping
failure stops without opening a broker session. QuoteSecurityId and QuoteSymbol
are mutually exclusive. The CSV has no ISIN field: this verifies provider symbol
to ID only, not local Nifty-500 membership or corporate-action lineage.

This preparation changes scripts only; do not rebuild the already accepted app.
Run the launcher after pulling. It can capture mapped stale data now; complete
freshness acceptance during a normal market session. No exception is raised just
because a well-formed returned quote is stale; fresh remains false and execution
is disabled. The quote object's mappingVerified remains false until Java/local
universe integration; report.quoteMapping describes only the public master lookup.

Then batch the remaining callback/lifecycle negatives and quote failure cases;
finally integrate the real quote into the combined Telegram ACCEPT/REJECT/expiry/
duplicate/unauthorized review test. G6 acceptance records review only. Paper
reservations, fills, costs and P&L integration follow; live orders remain disabled.

## Approved mobile authorization requirement (21 November 2026)

When broker login or holdings authorization is required, Telegram presents an
Authorization required button. The user completes OTP/TPIN on the official
Paytm/CDSL page on their phone, not in Telegram. MarketBrain verifies the
provider result and rechecks request expiry, quote freshness, account state and
risk before continuing. Expired approvals are not replayed after authorization.
This is approved future scope, not implemented functionality.

Schedule this in G4 session/mobile callback work, before enabling unattended
broker operation; holdings authorization is additionally a pre-live SELL gate.
Keep G6 paper review separate: paper fills do not require broker authorization.
Provider-supported phone callback/redirect and eDIS completion contracts remain
to be verified. The current localhost callback works only in the spare laptop's
browser. Do not expose it unchanged or collect OTPs through the bot. Use an
opaque, short-lived, single-use owner-bound link; validate callback/state,
reject replay, keep tokens server-side, and notify only sanitized outcomes.

Acceptance: successful phone login/authorization, wrong-owner/expired/replayed
link rejection, cancellation, provider failure and timeout, pending-request
expiry during authorization, and fresh revalidation after completion. No promise
of permanent login; session expiry and provider authorization remain respected.

## Automated application boundary batch

The reviewed queue job paytm-denial-recovery in FailureFixture mode now runs
seven fixed loopback checks: status and quote reject missing/wrong tokens,
cookie-less callback and repetition reject, and invalid browser code rejects.
It uses no real credentials, does not create/lock sessions or change tasks, and
cannot contact broker endpoints. Each call is bounded to eight seconds. Report
includes only expected/actual HTTP codes, no-store and pass/fail. Observe mode
continues collecting the latest compact login/quote report. These are partial
runtime boundary evidence, not valid-cookie replay, expiry or restart proof.
Runtime result: all seven boundary checks accepted on spare through job
73838720-3697-4df6-b4a5-7d2feebd0799; 0.583 seconds for probes. No manual
script/report transfer was needed. Remaining valid-session cases are unchanged.
