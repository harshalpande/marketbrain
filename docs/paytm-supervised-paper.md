# Supervised paper workflow: 20 November 2026 scope decision

The owner has explicitly prioritized a working supervised paper application over
unattended clock reliability. VPS UTC is accepted as the reference for this
prototype. Windows NTP synchronization, laptop/VPS offset screens, collector
publication and G3 lifecycle completion are not prerequisites for this path.
This is a scope decision, not evidence that deferred tests passed.

## Delivery sequence and acceptance

| Milestone | Current state | Runtime acceptance |
| --- | --- | --- |
| Supervised login and protected account read | Implemented; local tests passed; spare deployment pending | Owner login, one-use callback, read token exchange and account-read HTTP response |
| Real quotes | Next | Verified instrument mapping, actual provider timestamp and price; missing/stale quote rejection |
| Combined Telegram actions | Pending | ACCEPT, REJECT, 100-second expiry and duplicate rejection in one batch |
| Paper execution and portal | Pending integration | Virtual cash/holdings, costs, fills and portal reconciliation |
| Unattended lifecycle and clock reliability | Deferred | Resume after supervised workflow works |

The original accepted checkpoint score remains G1 100%, G2 100%, G3 80%,
G4/G5/G6 0% (14/30 accepted). New code is not runtime acceptance. There is no
claim of prediction accuracy, complete paper integration or live-order readiness.

## Implemented login behavior

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
& .\ops\windows\StartPaytmSupervisedLogin.ps1
```

The deployer retains the current Compose project/overrides, builds before
replacing the application and waits for health. The launcher requests the paper
read token, developer API key/secret and encrypted OpenSSH **clock** key path.
These stay on the spare laptop. Supply the clock-key passphrase only in the
native SSH prompt and complete the browser login there. No PuTTY copying is
needed. The gateway and collector must initially be stopped/disabled; existing
failure markers are preserved rather than silently reset.

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
