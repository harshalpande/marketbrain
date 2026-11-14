# Isolated Java timing guard after E264

The polling correction passed on the spare laptop: config/resync explicitly succeeded, all three status observations report leap0/stratum5/error0, same server with adaptive polling flag0x8, original service ACL and Running/Automatic state preserved. Task removed; rollback not needed. The reported26.328ms phase offset is a service estimate, not an independent UTC error bound. `timeServersChanged=true` compares the complete peer string: only the flag changed. This does not establish long-term drift or restart persistence.

## Next engineering batch

PaytmDiagnosticTimingGuard is a plain Java class with injectable wall/monotonic clocks. It has no Spring annotation, endpoint, network client or production caller. This batch compiles only that class and its standalone verification harness into a unique temporary directory. It does not rebuild/restart the running application, mutate time settings, inspect credentials or call a provider/database.

The diagnostic engineering policy uses a30-second health-evidence TTL,100-second lease, four-request budget and five-second offset/discontinuity screen. These values exercise boundary behaviour and are NOT approved trading tolerances. Future integration must specify a trusted health source and reviewed runtime policy. The observe API accepts synthetic evidence here; it does not authenticate operating-system or VPS observations.

The39 deterministic checks cover missing evidence, explicit arm/lock, exhausted budget, unhealthy clock/transport, NaN/infinite/inverted/out-of-range offsets, forward/backward/extreme wall jumps, stale-evidence boundary, lease expiry despite health renewal, monotonic reset, replay, wrong boot, null evidence and fresh evidence not silently retaining a lease after a jump. Refresh does not arm a locked guard. The implementation is synchronized for serialized state transitions; this harness does not establish production concurrency or transport integration.

## Spare-laptop script

Use PowerShell7. Existing native JDK21+ is required (the spare used it for earlier numerical tests). No automatic installation, PuTTY, Pageant, credentials, broker access or Docker deployment.

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
& '.\ops\windows\TestPaytmTimingGuardBundle.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-time-repair-b0bbe132fade4898bc90ea64d6659f38.json'
```

Expected: TIMING_GUARD_ENGINEERING_PASSED_INTEGRATION_PENDING. Normally seconds; compilation/run have60/30-second deadlines. Share the ONE paytm-timing-guard JSON, including on failure. Source hashes, compiler/run output, elapsed time and assertion count are embedded. Temporary compiled classes stay in the unique local temp directory; they need not be shared. Matching java.exe is selected alongside javac, and JVM environment options are stripped by the existing process helper.

## Verification and subsequent work

Local native Java22 compilation with --release21 passed all39 checks. The full PowerShell7 bundle passed with the accepted E264 receipt. No runtime service changes were performed during local verification.

After this engineering verification: review/integrate the guard into the credential-free application route with authenticated health evidence, test blocked/expired/jumped clocks and no direct fallback in the actual application, and verify startup wiring/restart lock. Those are still pending, as are production timing policy and durable clock-health evidence. G3.5 remains open. No percentage credit is awarded for an unconnected class: groups100/100/80/0/0/0,14/30=46.7%.
