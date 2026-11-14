# Health publisher contract after E268

## Accepted real evidence

The live rehearsal passed all three rounds, with collection durations 2.001, 1.681 and 1.705 seconds. Full interactive run elapsed 97.799 seconds. Windows last-good-sync age was 219-227 seconds against the 2108-second diagnostic limit; VPS NTP confirmed yes. Java-minus-VPS offset intervals were within approximately -1.071 to +0.122 seconds. The Windows proxy returned TLS-verified HTTP 503 in every round; this does not establish API readiness. Settings/container unchanged, no health submitted, no orders, Pageant cleanup owner-confirmed. All eight source hashes match d2c5cf1. See evidence/paytm-live-health-accepted-20261115.json.

## Publisher implementation

PaytmHealthPublisher.ps1 defines a one-shot client; import does not activate it. The fixed local health endpoint uses a separate in-memory token, no proxy or redirect, two-second HTTP timeout, bounded response contract and redacted errors. No token is provisioned or written by this change.

The sequence is challenge, fresh trusted collection, one submission. Collection never starts before a valid boot-bound challenge. Total challenge/collection time must stay below eight monotonic seconds. The collector callback is trusted code, not a saved-report importer. The live collector assessment is recomputed. The current rehearsal's Windows-only TLS evidence is deliberately insufficient: the adapter must separately establish applicationTransportVerified before healthy publication can occur. This flag is a trusted-adapter assertion, not independently proven by the publisher. A future Java-side collector must implement it; do not add it to an old JSON.

Failed, stale or unconfirmed collection submits unhealthy flags with sanitized finite bounds to revoke permission. A failed HTTP submission means lock is UNCONFIRMED; the client makes no automatic retry and does not claim revocation. Java's existing health expiry remains the server-side bound. Healthy evidence never arms the route. Receipt boot identity, accepted status and disabled order authority must match the contract.

## Verification and limits

15 local fixtures passed: fixed local HTTP contract and error redaction; healthy submission; eight-second expiry; collector exception; Windows-only transport refusal; unsynchronized status; TLS failure; stale synchronization; invalid numeric bounds; challenge failure/invalid challenge; submission failure; wrong-boot receipt; server rejection. They exercise the actual publisher orchestrator with network/collector boundaries replaced. They check ordering, no retry, sanitized errors and no route/order actions. They are not live HTTP, credential, unattended-task or Java-container integration evidence.

The spare script repeats these fixtures without network calls, Pageant, Docker interaction or application changes and produces one compact JSON. This is a quick publisher-client compatibility test, not another live clock collection. After it passes, integration still requires protected credentials, a narrowly scoped unattended VPS clock reader, actual Java transport evidence and staged deployment. G3.5 remains open; do not deploy the main application from this source yet.

## Spare laptop

Use PowerShell 7; no PuTTY/Pageant action or rebuild is needed.

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
& '.\ops\windows\TestPaytmHealthPublisher.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-live-health-20261115-022556-78ae275dd4234715b40498b204109820.json'
```

Expected PUBLISHER_CONTRACT_PASSED_RUNTIME_PENDING, checks=15. Share the one paytm-publisher JSON. No prior live test needs rerunning.

Readiness: G1 100%, G2 100%, G3 80%, G4-G6 0%; 14/30 = 46.7%. Engineering substeps are recorded without counting an unverified runtime checkpoint as complete.
