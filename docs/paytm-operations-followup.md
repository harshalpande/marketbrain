# Windows clock and VPS maintenance follow-up

**Superseded retry instructions:** E162 owner follow-up completed capture in198.117s; elevation passed and VPS index refresh succeeded. Windows service start failed at OpenService error5, so resync did not run. Use the [Windows-only diagnostic](paytm-windows-time-access.md) next, not another combined refresh. Seventy package candidates remain for separate reviewed maintenance.

**E161 correction:** owner run `f5b7892d6d0049cd82703ce431fa4d53` stopped at `OPS_ADMIN_POWERSHELL_REQUIRED` in 0.009 seconds, before confirmation or changes. Use the new UAC launcher below instead of invoking the runner directly. Administrator-account membership is not an elevated process. The launcher uses [Start-Process -Verb RunAs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.5), never bypasses UAC or execution policy, and opens a visible PowerShell 7 window. Launch success is not review success. No runtime progress credit is added.

2026-10-22, E159/E160. [Reviewed snapshot](evidence/paytm-operations-spare-review-20261022.json) completed in 134.148 seconds: host/config hashes matched, expected VPS-bound public IP, proxy inactive, no listeners/watchdogs, VPS reported NTP synchronized. Findings: clock disagreement, 70 cached upgrade candidates, old Release metadata and an incorrect proxy-package lookup. Windows OpenSSH exists; its agent is stopped/disabled. This is not a failed application-route test and does not require repeating E157's accepted 8/8 stages.

The owner says the spare laptop's clock may be wrong and agrees to correct it. **Treat the VPS as the provisional reference and leave its clock unchanged.** NTP=true is useful evidence, not absolute accuracy proof. Windows' clock/source must be checked rather than assuming the VPS is at fault.

## Changes and boundaries

1. Fix `dpkg-query` to inspect **tinyproxy-bin**, the package our installer actually installs. The previous UNKNOWN was a collector defect, not evidence of a broken proxy. The default operations collector remains read-only.
2. New follow-up runner requires elevated PowerShell 7, the exact reviewed E159 report hash and owner confirmation `SYNC_AND_REFRESH` with clock-sensitive jobs/approvals/tests idle. It records Windows Time service state, queries status, starts W32Time only if stopped and not disabled, then calls `w32tm /resync /rediscover` using the **existing configured source**. No registry/time-peer/timezone rewrite, manual Set-Date, forced service re-registration or VPS clock change. A disabled service is retained for policy review, not automatically reconfigured. Each native command is bounded to 30 seconds; service-running wait is 20 seconds. A started service is left running; original state and attempted actions are recorded.
3. Before/after status and source, exit codes and timings are retained in the one report. Source names may include a local/domain time-server hostname; review before public sharing. A zero resync exit is **not proof of clock accuracy**. Query/source/clock findings still need review. Windows failure does not discard the separate VPS observations.
4. The VPS performs identity/configuration/stopped-proxy preflight, then **APT index refresh only**, with any fetch error treated as failure, no retries, bounded network/lock wait and 180-second overall refresh deadline. Console heartbeat every five seconds; outer payload limit 420 seconds plus ten-second forced termination grace. It does not install/upgrade/remove packages, change sources, reboot, start the proxy or modify its policy. It uses existing configured repositories and normal APT behavior; no new repository or credential is introduced.
5. After refresh, capture a simulated upgrade count and at most 200 package/current/candidate version rows, plus the corrected proxy version and current operational state. Refresh failure stays explicit: candidates may be stale. Raw repository output/URLs are not copied into shared evidence. Successful refresh does not require repository Release-file mtimes to become today's date; the old age is retained as information rather than a false failure. Package updates remain a separate reviewed action; zero simulated upgrades is not a vulnerability audit.
6. Start the Windows/VPS comparison window **after** the resync attempt. Record monotonic collection time and flag wall-clock movement during collection. Manual timestamp comparison is coarse, not proof of 15-second quote-age accuracy. No clipboard timestamp is used to set either clock. VPS-bound IP remains distinct from application/proxy egress.

These operations follow [Microsoft's W32Time command guidance](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/Windows-Time-Service-Tools-and-Settings) and the [Debian APT update/simulation documentation](https://manpages.debian.org/trixie/apt/apt-get.8.en.html). No broker credentials, live quotes, orders, paper-account writes, SSH-agent activation, unattended keys or application rebuild are part of this package.

## Complete spare-laptop handoff

Keep clock-sensitive jobs, active approvals and tests idle. Open ordinary **PowerShell (5.1 or 7)** on the spare, and a verified **marketbrain-admin PuTTY** session. PowerShell 7 must already be installed and discoverable. The launcher requests elevation for you. Do not load the gateway PPK or start a tunnel.

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
$evidence = 'C:\MarketBrainData\Review\paytm-operations-20261022-192224-b5f4ea70636047d6ad6ab4dc378a505f.json'
if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) { throw 'Reviewed operations report missing.' }
& '.\ops\windows\StartPaytmOperationsFollowUp.ps1' -OperationsEvidencePath $evidence
```

1. Approve the Windows UAC prompt. Continue in the **NEW administrator PowerShell 7 window**, not the original launcher window. If UAC is cancelled, no review starts. All references to PowerShell below mean this new window. Type `SYNC_AND_REFRESH` only when the stated jobs are idle. Windows time checks/resync run first. Do not rerun automatically if they fail; the report will preserve their outcome while collecting VPS evidence.
2. At the next prompt, manually run `sudo -v` in **PuTTY**, enter the sudo password there, then return to **PowerShell** and press Enter. The VPS command is copied after this step.
3. Paste into **PuTTY**. Index refresh and inspection run automatically. **No START-TEST, STOP or SERVER_READY prompts.** Allow the heartbeat to run; do not interrupt a package-index refresh just because download speed is slow. It is bounded.
4. Copy only `BEGIN_PAYTM_OPERATIONS_<current ID>` through `END_PAYTM_OPERATIONS_<current ID>` when printed, excluding the earlier progress lines. Return to **PowerShell** and press Enter within 20 minutes. If no complete block was produced, return the visible error text through that prompt for a failure report; do not launch a second refresh blindly.
5. Share the ONE `paytm-operations-followup-...json`. `FOLLOWUP_CAPTURED_WITH_FINDINGS` can be the correct result when upgrades remain; it does not mean the refresh failed. No updates are automatically applied.

## Verification and next milestone

E161 launcher: 22 mocked assertions under PowerShell 7 and 21 under Windows PowerShell 5.1, covering explicit RunAs, quoted/Unicode paths, no command injection, missing inputs/runtime, cancelled/failed elevation and clear handoff. No real UAC or resync was invoked locally. The existing 44 and 52 assertion suites were rerun successfully. Real UAC and corrected runtime acceptance remain pending owner execution.

44 new PowerShell assertions include eight mocked follow-up workflows: clean, upgrade findings, time failure, refresh failure, cancellation, missing elevation, incorrect prior evidence and malformed receipt. Windows helper fixtures cover start/disabled service, configured-source-only resync, command failure/timeout and post-query capture. Existing 52 operations assertions remain passing. The current Bash suite has 31 assertions (supersedes its previous 20), including exact tinyproxy-bin lookup, refresh mode guards, failure exit capture and safe candidate extraction. Actual Windows resync and VPS refresh have **not** run locally.

Review the fresh report, resolve any remaining clock/maintenance issue in a bounded package, then provision and verify the [unattended gateway](paytm-unattended-gateway-plan.md) before real Paytm login. The accepted transport/application tests stay accepted. No whole-project completion percentage or guaranteed retry count follows from this local correction.
