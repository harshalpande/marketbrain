# Unattended gateway foundation: one local engineering bundle

**Accepted E185, 2026-10-23:** spare report passed79 checks,12 negative cases,31 settings/space paths in2.335s, failure null. Do not rerun this bundle. Next [controlled Windows account/agent setup](paytm-gateway-account.md); [group percentages](paytm-readiness-progress.md) are G1=100%, G2=20%, G3–G6=0%. Earlier run instructions below are retained for reference.

## Current outcome and purpose

E183 accepts the owner's maintenance/reboot evidence. Both v2 receipts were independently reparsed: boot changed, installed targets verified, stale services **6 to 0**, stale sessions **4 to 0**, no failed services after reboot, gateway still static/inactive and NTP synchronized. Postcheck collection took 28.444s, not measured downtime. Guest microcode remains explicitly unassessed/provider-managed. **Do not repeat maintenance, installation or reboot.**

E184 adds the first unattended supervisor **engineering foundation**, not an installed supervisor. The next spare-laptop run batches the state/recovery rules, native owned-process cleanup, exclusive locking and the installed Microsoft OpenSSH client's effective configuration into one JSON. No VPS session, Pageant key, administrator password, broker credential, service change or real connection is needed.

Why this precedes installation: an automatic reconnect must not retry a changed host key, commandeer somebody else's listener, continue showing a stale connection as healthy, or restore trading authority. Also, the spare has a different OpenSSH version from development; we check its actual `ssh -G` output rather than assume our configuration is interpreted identically.

## Implemented and tested together

| Area | Implemented check | What it does not yet prove |
|---|---|---|
| Recovery policy | Monotonic deadlines; 5/10/20/40/60s capped backoff; 30s connect/health deadline; 60s sustained-health reset avoids flapping | Real network recovery or an operational polling loop |
| Security failures | Host-key/key/credential/TLS/destination/configuration/listener errors latch blocked; unknown failures also block | Native error classification and production observation adapters are not wired |
| Stop and exclusivity | Stop latch; exclusive file lock; cancel and timeout terminate only the owned native fixture, preserving another child | Durable kill switch across scheduled-task restart; exact-account ACLs |
| SSH contract | Fixed public host/user, 127.0.0.1:18889 to 127.0.0.1:18888, strict known-hosts, public-key-only, no session/PTY/agent forwarding or inherited SSH config | Validated known-hosts contents, authenticated connection or server-side denials with the new client |
| Native compatibility | Actual Windows client `-G`, 31 required settings; paths with spaces; 12 negative mutations from actual output | Key custody, service/task permissions, logoff or cold-boot recovery |
| Metrics and authority | Named test results, elapsed time, installed client/agent status, source hashes; brokerReady/ordersEnabled always false | Authenticated API/quote readiness; an HTTP503 is not readiness |

The state engine is sourceable and has no startup side effects. It emits actions; **there is no production runner, task installer or credential adapter in this milestone**. Future integration must execute actions, observe owned listener/authenticated pinned SSH/TLS health independently, and use Stopwatch time. Synthetic `HEALTH_OK` inputs are test evidence, not real authentication evidence. The host-key file must later be validated against the previously verified SHA256 pin; its placeholder path here is not a trust decision.

We reuse the existing owned-process helper, not process-name termination. Test fixtures are hidden short-lived PowerShell processes; their one temporary lock file/directory is removed. The only retained artifact is the report. The helper's existing output-capture design is acceptable for these bounded known fixtures and `ssh -G`; a long-running production SSH adapter still needs bounded streaming logs and cancellation review.

References: [OpenSSH configuration semantics](https://man.openbsd.org/ssh_config), [Microsoft Windows key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement). Documentation supports the design, not proof of scheduled-account agent persistence. No Windows OpenSSH Server installation is needed.

## Spare-laptop instructions

Use **PowerShell 7**, ordinary/non-elevated. Close no application. Do not start PuTTY/Pageant, load any key, reboot or rerun maintenance.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 first.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch; stop for review.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Worktree not clean; preserve changes and stop.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Do not run the test.' }
& '.\ops\windows\TestPaytmGatewayFoundationBundle.ps1'
```

Expect progress 10%, 70%, 100% and `GATEWAY_FOUNDATION_PASSED_PROVISIONING_PENDING`. Local development run took a few seconds; the spare's timing is measured, not promised. Share the **one `paytm-gateway-foundation-*.json` path printed by this run** from `C:\MarketBrainData\Review` even if it fails. No clipboard exchange, typed START/STOP markers or source evidence file selection.

## Next work and unchanged acceptance groups

1. Maintenance: **accepted E183**.
2. Unattended gateway: foundation and spare compatibility accepted E185 (G2.1,20%). Next is the explicit-consent dedicated Windows account/agent batch E186. Key custody and scheduled-supervisor/VPS lifecycle remain pending; do not activate these from foundation evidence alone.
3. Real lifecycle/fail-closed acceptance: still pending, including process/network interruption, safe stop, logoff/cold boot, clock drift, actual OpenSSH restrictions and application no-fallback behavior.
4. Paytm login/token/callback: pending.
5. Read-only fresh quotes: pending.
6. Combined Telegram ACCEPT/REJECT/expiry: pending, review-only policy unchanged.

This is still **1/6 acceptance groups complete (16.7% of this Paytm-readiness checklist)**, not 16.7% of MarketBrain or a guarantee of five runs. Engineering assertions do not close groups 2/3. Live order submission is excluded; return to paper-fill/cost/P&L integration after these gates.
