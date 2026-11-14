# Java-owned health transport after E269

E269 accepts the spare publisher contract: 15 fixtures, 0.201 seconds, zero network calls, no credentials/application changes. Three source hashes match d22592c. Evidence: evidence/paytm-publisher-accepted-20261115.json.

## Integration change

The health bridge now requires its own successful credential-free TLS HEAD through host.docker.internal:18889 before it accepts healthy clock/transport evidence. It does not rely on a publisher-supplied applicationTransportVerified flag. Only well-formed, matching, unexpired, one-use challenges with healthy flags and valid clock bounds trigger the fixed probe. It cannot select a destination, supply broker credentials or execute orders.

The probe uses the existing required-proxy transport with a two-second connect/request deadline. The normal diagnostic transport retains its previous timeout. Probe failure or exception rejects health and locks authority; sensitive exception text is not returned. Time spent probing counts toward the original ten-second challenge deadline, checked again after completion. Late TLS success cannot refresh health. Replays and unhealthy/malformed submissions cannot trigger another probe. A root HTTP 503 with verified TLS establishes transport only, never Paytm API readiness.

Receipts include healthContractVersion SERVER_TRANSPORT_V2. The publisher checks that version before collecting or submitting, recomputes fresh clock assessment, and waits at most three seconds for the submit response to accommodate the server probe. Java remains the transport authority. It still trusts the protected publisher for OS synchronization/clock measurements; this is not independent attestation of those facts. No real publisher credential or unattended reader is provisioned by this change.

Healthy evidence never arms the route. The feature remains disabled by an empty health token. Do not rebuild the main application yet: staged deployment and credential configuration must be delivered together. The running application's version is unchanged by this test.

## Verification

34 local JUnit tests passed, including the 39 guard assertions and prior controller/proxy checks. New cases cover caller claim overridden by Java TLS failure, redacted probe exception, expiry during the probe and replay/unhealthy input avoiding network work. The existing actual loopback transport suite tests mandatory proxy, TLS refusal and no direct fallback. Successful external TLS is simulated in these isolated Java tests, not claimed observed in the deployed main process.

16 local publisher fixtures include rejection of an older health contract; four mocked Docker-controller workflows cover pass/build/run/cleanup failures. The spare batch verifies the Java tests in the isolated image using --network none, no ports/mounts or application/database access. Build may download dependencies. The temporary container is removed; build image retained for cache. One JSON embeds timings, logs, source hashes and cleanup.

## Spare steps

Start Docker Desktop. Use PowerShell 7. No Pageant or PuTTY steps are required; no live clock collection needs repeating.

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
  -EvidencePath 'C:\MarketBrainData\Review\paytm-publisher-4c9498d50d1247e0b8f56c9f75c9308c.json'
```

Expected JAVA_HEALTH_TRANSPORT_TESTS_PASSED_DEPLOYMENT_PENDING, junitTests=34. Share the one new paytm-timed-route JSON. Do not rebuild the main application if the fixture fails.

Remaining runtime work: protected health token and staged application deployment; actual Java TLS/health publication with rejection/expiry/restart checks; narrowly scoped unattended clock collection and publishing lifecycle. These remain part of G3.5. G1 100%, G2 100%, G3 80%, G4-G6 0%; 14/30 = 46.7%. No progress credit is assigned for runtime checks not yet performed.
