# Paytm operational snapshot before credentials

**E159/E160 update:** the owner snapshot was captured with findings in 134.148 seconds. VPS IP/configuration/stopped state passed; clock disagreement and cached updates need follow-up. The proxy-version UNKNOWN is our wrong-package query (`tinyproxy` versus installed `tinyproxy-bin`), now corrected. Owner directs Windows clock correction first, leaving VPS time unchanged. Use the [combined follow-up](paytm-operations-followup.md), not another default snapshot. Historical instructions below describe the earlier read-only run.

2026-10-22, E157/E158. Main Spring route accepted **8/8 stages in456.253s**. This supersedes E156's spare-pending state, not the open login/data gates. The application locked after closed-tunnel and stopped-proxy failures, recovered only after rearm, restarted with a new boot identity and remained locked. INR100000 cash, zero reservation and ledger revision0 were preserved. Root HEAD503 remains an API-readiness warning; no authenticated endpoint was tested.

## Why this run and what it achieves

Collect the remaining operational facts in one report before introducing broker credentials: fixed VPS public-IP observation, current clock synchronization, maintenance evidence and stopped gateway/watchdog state. The owner chose **unattended gateway design before login testing**; the report also reads Windows-owned OpenSSH client metadata and agent service status, never keys, to inform that design. This is not a repeated tunnel or application test. No rebuild, restart, service start, settings change, package refresh/install, key loading, broker request, order or paper-account write. Only the single Windows evidence JSON is written by the collector; normal OS logging may occur.

The script uses a verified administrator PuTTY session and pinned host fingerprint. One bounded HTTPS request to api.ipify.org binds to130.250.191.137 and disables curl config/proxy environment/redirect following. This observes **VPS-bound egress**, not application/proxy egress or Paytm's view of the source address. The unchanged proxy Bind configuration and accepted application transport are complementary evidence, not a fresh end-to-end IP observation. No temporary allowlist change is made.

Machine-readable [timedatectl show](https://manpages.debian.org/trixie/systemd/timedatectl.1.en.html) provides NTP synchronization state. Server time is compared with the Windows manual collection interval plus five seconds tolerance; this is a coarse clock sanity check, **not proof of15-second clock accuracy**. Windows clock accuracy is not independently measured. A response outside the interval, reversed local clock, unknown NTP status or no synchronization requires review.

[APT simulation](https://manpages.debian.org/trixie/apt/apt-get.8.en.html) counts planned cached upgrades without applying them. Oldest cached Release metadata mtime is an age clue, not the date of a successful index refresh. Seven days is a review heuristic, not a patch-policy certification. Zero cached upgrades or an absent reboot marker does not prove full patch currency or that a reboot is unnecessary. Future/unavailable cache dates, pending upgrades, unavailable versions and reboot markers are retained for one consolidated maintenance decision. No automatic correction is authorized by this snapshot. [curl controls](https://curl.se/docs/manpage.html) preserve TLS verification and bound the request.

Host/config identity, service inactive, no18888 listener, no remaining test watchdog units, no systemd drop-ins or pending reload are checked. A leftover inactive watchdog is a review finding, not silently deleted. These are point-in-time observations, not continuous enforcement.

## Exact spare-laptop procedure

1. Keep Docker/MarketBrain as they are. Open a verified **marketbrain-admin** PuTTY session using the existing admin PPK, not the gateway account. The RSA fingerprint remains `SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI`. Do not accept a changed host key blindly.
2. Run the following in **PowerShell7 on the spare**:

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
$accepted = 'C:\MarketBrainData\Review\paytm-application-route-20261022-182859-223cdc084de64c90a80c527032ac6879.json'
if (-not (Test-Path -LiteralPath $accepted -PathType Leaf)) { throw 'Accepted application report missing.' }
& '.\ops\windows\ReviewPaytmOperations.ps1' -ApplicationEvidencePath $accepted
```

3. At the first PowerShell prompt, go to **PuTTY** and run `sudo -v`; enter the administrator's sudo password there. Return to PowerShell and press Enter. It now copies a read-only command.
4. Paste into **PuTTY** and press Enter if needed. It runs automatically, normally under a minute with an outer180-second limit. There is **no START-TEST, STOP, SERVER_READY or Pageant gateway-key step**. If it prints STOP or no complete report, do not run a gateway installer; return to PowerShell with the displayed output for a failure report.
5. Copy exactly `BEGIN_PAYTM_OPERATIONS_<current ID>` through `END_PAYTM_OPERATIONS_<current ID>`, including both lines. Return to **PowerShell** and press Enter within20minutes. Do not paste the report as a shell command. The script reads the clipboard.
6. Share the single `paytm-operations-...json`. `SNAPSHOT_CAPTURED_WITH_FINDINGS` means evidence was collected and needs review, not that corrections were applied. Even the no-findings status retains login/maintenance-review pending. No secrets are requested or recorded. The exact previously accepted application report hash is pinned; changed evidence requires review, not bypassing its guard.

## Verification and next milestone

52 PowerShell assertions include four fully mocked collection workflows: clean, operational findings, malformed/secret-like clipboard and wrong accepted-report hash. 20 Bash offline assertions cover identity/root guards, output filtering, fixed external-request arguments, cached-upgrade simulation and unavailable commands. No real VPS/network execution is claimed locally.

Review the resulting findings together, then implement and verify the [unattended gateway design](paytm-unattended-gateway-plan.md) before login, as the owner explicitly selected. The collector introduces no persistent keys or login enablement. Subsequently implement bounded real callback/token lifecycle, read-only quotes and combined Telegram ACCEPT/REJECT/expiry, before resuming paper execution integration. Live order placement remains separately authorized and is not required to return to paper development. Remaining rounds depend on findings; no fixed retry count or full-project percentage is promised.
