# Guarded diagnostic-route integration verification after E265

E265 accepts the spare-laptop isolated guard:39 deterministic checks, compiler/JVM exit0,6.514s, five source hashes verified. This establishes the test behaviour, not runtime enforcement.

## Changes and deployment boundary

PaytmApplicationRoute now checks the timing guard before calling its fixed credential-free HEAD transport and validates timing again afterward. A late/stale or clock-jumped response is discarded. Explicit lock, unhealthy transport and revoked health remove permission; health refresh cannot restore a revoked in-flight lease. Controller token/header/host rejection and mandatory proxy transport remain in place. Boot identity and evidence sequence prevent old-instance/replayed evidence. No endpoint accepts health evidence.

The Spring constructor deliberately starts without health evidence: arm returns TIMING_BLOCKED until a trusted runtime health provider is implemented. Synthetic health is injected ONLY by tests through the package-private Java method. The running application is unchanged by this script. **Do not rebuild/deploy the main application yet:** deploying this source now would block the existing diagnostic arm/head workflow. This batch runs in an isolated image, without host mounts, published ports or external network at execution. No broker credentials or orders.

The30-second health TTL,100-second diagnostic lease, four-call budget and five-second clock screen remain engineering policy, not trading approval limits. Previous20-minute diagnostic lease is replaced in this guarded source; existing runtime still runs its deployed version. Application-wide health attestation and policy approval remain pending.

## Test batch and limitations

20 JUnit tests cover Spring bean construction, controller boundaries, route timing before/after transport, fresh health during a revoked request, restart locking, missing/stale/unhealthy evidence, explicit rearm, existing call budget and actual loopback proxy-denial/TLS/no-direct-fallback fixtures. They include the39 guard assertions from E265. The standalone summary reader validates three fixed Surefire reports with zero failures/errors/skips and20 total tests. Build runs the tests once to cache dependencies; the container repeats them using Maven offline with `--network none`.

Local native Maven tests passed; four mocked Docker-controller workflows cover success, build failure, run failure and cleanup failure. The real isolated Docker image/run is the spare-laptop validation requested below. This is not a live provider or main-container test.

## Spare-laptop script

Start Docker Desktop, then use PowerShell7. No Pageant, PuTTY, Windows time changes, main-container restart or broker credentials are needed. First build may download Maven/image dependencies; build timeout5minutes, test timeout2minutes. Retained build image provides cache; the disposable test container is removed. No unrelated resources are pruned.

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
& '.\ops\windows\TestPaytmTimedRouteBundle.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-timing-guard-b435aa1bbc1d4b5eb6163574525cc27d.json'
```

Expected: TIMED_ROUTE_INTEGRATION_TESTS_PASSED_DEPLOYMENT_PENDING. Share ONE paytm-timed-route JSON. It embeds build/test logs, source hashes, summary, elapsed time and cleanup status. On timeout/failure share the same report; do not rebuild the main application as a workaround.

After acceptance: implement the trusted runtime health evidence adapter, verify its authentication/freshness/clock-drift contract, then stage actual application deployment and guarded route verification. G3.5 remains open;14/30=46.7%, group percentages100/100/80/0/0/0. Local/in-image tests do not close a runtime checkpoint.
