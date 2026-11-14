# Authenticated diagnostic health input after E266

Accepted as E267. Continue with [live collector rehearsal](paytm-live-health-collector.md). The following describes the historical bridge batch.

E266 accepts the spare-laptop isolated Docker run: 20 JUnit tests including 39 guard assertions, 199.867 seconds, no failures, disposable container removed. All 15 source hashes match d7c63e2 (including Windows line-ending normalization). See evidence/paytm-timed-route-accepted-20261115.json.

## Purpose and boundaries

The next batch verifies Java's health-input boundary before connecting the real collector. A separate health token (32?128 URL-safe characters, unequal to the paper read token) is required. It defaults empty/disabled and requires PAPER mode. No credential provisioning or main-application deployment is included. Fixed local Host and diagnostic header checks supplement authentication; Host itself is not proof of network origin.

POST /api/v1/paytm/route-health/challenge issues a random challenge tied to the current Java boot, valid for less than 10 monotonic seconds. POST submit consumes it, assigns the next server-owned sequence and passes clock/transport evidence to the guard. Expired, replayed, wrong-boot or unhealthy submissions revoke authority. Valid health does not arm or extend a diagnostic lease. Explicit arm is still required. Health refresh cannot restore a revoked lease. The bridge itself makes no network calls.

Authentication occurs before payload reading. The body is bounded to 2048 bytes, requires known length and JSON content type, and rejects missing/unknown/duplicate fields, null/coerced primitive values and trailing JSON. Boundary/authentication/malformed-input rejection does not mutate health; authenticated well-formed submissions consume the challenge. Responses are no-store and contain no tokens. This is a diagnostic interface, not order authority.

A challenge establishes the submission window, NOT the truth or age of the underlying measurement. The next implementation must collect current Windows synchronization, VPS/Java clock bounds and transport health using a trusted, protected publisher. It must prevent use of cached measurements, provision the separate token safely and validate runtime failure/recovery. Until then the main application must not be rebuilt from this source: its guarded route has no live health provider and remains locked.

## Verification

30 JUnit tests include the prior 20 plus 10 health-boundary tests: Spring disabled/configured construction, separate-token enforcement, explicit arm, replay, expiry, boot/challenge mismatch, bad clock bounds and unhealthy flags, no lease extension, auth-before-read, forwarding/size rejection, strict JSON and HTTP roundtrip. The suite includes 39 standalone guard assertions. Four mocked PowerShell workflows verify pass/build failure/run failure/cleanup failure. Local tests are engineering evidence only.

On the spare laptop the isolated image builds dependencies (network may be used), then runs Maven offline with --network none. No host volumes, published ports, running-application rebuild, database, broker credentials or order calls. Test containers are removed; the image remains for caching. The one report includes source hashes, build/runtime logs, timings and cleanup. Build timeout five minutes, runtime timeout two minutes.

## Spare-laptop handoff

Start Docker Desktop and open PowerShell 7. No PuTTY or Pageant steps are needed.

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
  -EvidencePath 'C:\MarketBrainData\Review\paytm-timed-route-23619cf7a5124c8aa3f92e8eec541eed.json'
```

Expected: HEALTH_BRIDGE_TESTS_PASSED_COLLECTOR_PENDING. Share the ONE new paytm-timed-route JSON. On failure share that report; do not deploy the main application as a workaround.

Paytm readiness remains 14/30 = 46.7%; G1 100%, G2 100%, G3 80%, G4?G6 0%. This batch prepares G3.5, without crediting an unconnected runtime collector. After acceptance: trusted collector and credential provisioning, then guarded application deployment and actual failure/recovery verification before Paytm login.
