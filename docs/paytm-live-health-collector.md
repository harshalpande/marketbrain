# Live health collector rehearsal after E267

E267 accepts 30 JUnit tests including 39 guard assertions on the spare laptop, 111.486 seconds and successful container cleanup. All 18 source hashes match 5eae02e. The report confirms no live collector, running-application changes or orders. Evidence: evidence/paytm-health-bridge-accepted-20261115.json.

## What this step establishes

The bridge needs fresh measurements, not a previously saved JSON. This read-only rehearsal collects three new rounds, each containing Windows Time service/status/source and last synchronization age, a nonce-bound pinned SSH VPS time/NTP response, the running Java account-read timestamp and a credential-free TLS HEAD through the fixed Windows gateway proxy.

The collector assesses each round against an eight-second collection budget, leaving two seconds of the bridge's ten-second challenge window for eventual submission. It does not issue a challenge or submit anything yet. A slow round produces findings; the threshold is not silently extended or retried. Each clock request must also meet the existing two-second delay and 0.1-second wall/monotonic movement screen. Windows/VPS/Java relative offset intervals must remain within five seconds. These are diagnostic engineering screens, not trading quote thresholds or proof of absolute UTC accuracy.

Windows Time must be Running/Automatic and report synchronization using the existing expected source. Last-good-sync age must be parseable and at most min(3600 seconds, twice the reported polling period plus 60 seconds). Unknown/localized status fails closed. This is a provisional collector screen; NTP status does not by itself establish absolute accuracy. Windows service configuration is compared before/after. Container identity/token are also checked for changes; tokens and account response bodies are never written to the report.

TLS probe uses Windows System32 curl with configuration loading disabled, fixed proxy 127.0.0.1:18889, explicit empty proxy-bypass list, HTTPS only, HEAD only, no redirects or credentials. It requires successful certificate verification, an HTTP response and loopback proxy peer. Root HTTP 503 can establish TLS transport but is not API readiness. This checks the Windows-to-gateway path, NOT Java transport health or current gateway process ownership. It cannot yet supply production transport authority.

## Scope remaining

This rehearsal uses the administrator Pageant key for read-only VPS clock observation, as the previous clock collector did. It does not install an unattended administrator login or add privileges to the restricted gateway identity. Next implementation must provide a narrowly scoped unattended clock reader, protect/publish a separate health credential, bind measurements to a live challenge and current Java boot, then verify actual guarded application deployment. Reports are diagnostic artifacts only and must never be replayed as live health. No acceptance credit for G3.5 until runtime integration is verified.

## Verification and handoff

Local verification: 21 PowerShell fixtures cover healthy/slow/stale/unknown-sync cases, clock movement, unconfirmed VPS NTP, malformed/out-of-range offsets, transport failure, mandatory proxy arguments and TLS response classification, plus real-controller pass/findings/failure paths with OS/network boundaries mocked. No external calls or system changes in those fixtures. Real environment collection is the next spare run, not claimed tested locally.

1. Keep Docker Desktop, the existing MarketBrain container and the managed gateway running. Do not rebuild/restart them for this test.
2. Open Pageant and load the original encrypted ADMINISTRATOR PPK for marketbrain-admin (not the restricted gateway key). Enter the passphrase only in Pageant. No PuTTY command needs pasting.
3. Run the script below in PowerShell 7. It checks the accepted E267 file, then asks HEALTH-CHECK. Type that only in PowerShell once Pageant is ready.
4. At the final prompt, remove only the administrator key if added just for this test; retain keys used by other sessions. Type KEY-REVIEWED in PowerShell.
5. Share the single paytm-live-health JSON, including if it reports findings or fails. It is checkpointed after each completed round. No automatic repair/retry is performed.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmLiveHealthCollector.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-timed-route-2c397f318f4744808491f291c471c59c.json'
```

Expected successful result: LIVE_HEALTH_COLLECTION_PASSED_PUBLISHER_PENDING. Usually about one minute after the prompt; individual calls have bounded deadlines. LIVE_HEALTH_COLLECTION_WITH_FINDINGS means capture completed but the screen did not pass: send the file without rerunning.

Paytm progress: G1 100%, G2 100%, G3 80%, G4-G6 0%; 14/30 = 46.7%. Application deployment, real Paytm login/quotes and combined Telegram review remain pending. No trades are enabled.
