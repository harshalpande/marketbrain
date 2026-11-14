# Live health publication and revocation

E272 accepts deployment in 195.378 seconds, including authentication, unhealthy input, replay, expiry and restart rejection. All eight source hashes match 6baf042. No rollback was necessary. The paper account is preserved and writer/route remain locked.

## Correction after E273

The first run stopped before publication because the shared Docker helper called a missing Save-Report checkpoint hook. This was a controller defect, not evidence of a Docker or gateway outage. The hook now delegates to Save-LiveHealth. Safe application helper error codes are preserved instead of replaced by a generic clock error. Rerun the same command below; do not redeploy. Final revocation/account/writer checks were not reached in the failed run and are not claimed as verified by that report.

## Purpose and limits

This test connects the already verified collector and publisher to the deployed bridge. Three fresh challenge-then-collect rounds check Windows synchronization, pinned VPS time, Java time and Windows fixed-proxy TLS. Java independently checks its own proxy TLS before accepting health. No saved report is replayed as health. The accepted activation report pins the deployed image; the script reads tokens privately from the validated container environment.

The route is locked before collection, never armed, and health is explicitly revoked in finally with an unhealthy submission and final lock. Failure to confirm revocation remains REVIEW_REQUIRED. A killed process cannot guarantee finally execution; server-side health expiry remains the bound. Run alone with no competing route diagnostic jobs. No application restart, deployment, time adjustment, login, quote or trade is performed. Successful TLS including root HTTP 503 is transport evidence, not authenticated API readiness. This diagnostic five-second clock screen is not a trading threshold.

The script preserves account, writer lock, container identity and time-service settings. It reports source hashes, timings, safe observations and publication receipts in one JSON; tokens and private keys are not reported. Application configuration is unchanged; in-memory diagnostic health is temporarily changed and then revoked. Unattended collection is not installed here.

## Verification

Seven controller fixtures exercise the real publisher with mocked OS/Docker/SSH/HTTP: success, unhealthy clock input, collection failure, server rejection, account drift, final revocation failure and native discovery failure. Discovery uses the real shared helper and checkpoint hook; external processes are mocked. They verify failure status, cleanup and absence of tokens in evidence. Existing collector and publisher component checks remain applicable. Runtime acceptance requires the spare-laptop report.

## Spare laptop steps

1. Keep Docker, MarketBrain and the managed gateway running. Use PowerShell 7 and keep other tests idle.
2. Open Pageant. Add the original encrypted administrator PPK for marketbrain-admin. Enter its passphrase only in Pageant. This is the administrator key, not the restricted gateway key. No PuTTY terminal commands are needed.
3. Execute:

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
& '.\ops\windows\TestPaytmLiveHealthPublication.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-health-activation-e2d7180e5f49468fbeddb080c4e1098a.json'
```

4. Type HEALTH-CHECK in PowerShell when prompted. Wait for the three automatic rounds.
5. At the cleanup prompt, remove only the administrator key you added for this test if no other session needs it. Keep the encrypted PPK and unrelated keys. Type KEY-REVIEWED in PowerShell.
6. Share the ONE paytm-live-publication JSON printed at completion, even on failure.

Expected LIVE_HEALTH_PUBLICATION_PASSED_UNATTENDED_PENDING. No automatic rebuild or repeat. Successful publication still leaves unattended health-reader custody/lifecycle and application stale-health runtime acceptance pending before G3.5 closure.

G1/G2/G3/G4/G5/G6 remain 100/100/80/0/0/0%; 14/30 (46.7%). This measures accepted Paytm checkpoints, not whole-project completion.
