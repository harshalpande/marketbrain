# Diagnostic health-token custody

E288 accepts the scheduled health-account signing and VPS clock test in 37.204 seconds. Its ten source hashes match 2a5d076. The temporary task was removed; only health SID ending 1011 gained batch-logon allow, with deny rules unchanged.

The next batch gives that account encrypted custody of the existing Java diagnostic health token. This token authenticates local route-health reports; it is not a Paytm credential or the paper-account read token. The collector will need it to report health without an operator typing credentials.

## What the batch verifies

1. Accepted receipt hash, exact enabled health account and ownership, protected parent/work ACLs, absence of an earlier token installation, local Docker context and the existing running workspace container. Paytm remains disabled and the application route must already be locked.
2. Read the existing health token privately from Docker inspection. Pass it only in the first child's process environment, removed by the child immediately after reading; never interpolate it into script source, command arguments, evidence or persistent plaintext files. Parent environment is unchanged. Existing private process transport carries only non-secret code.
3. Under the exact non-admin health identity, encrypt with Windows CurrentUser DPAPI and verify a round trip. Write ciphertext only. Confirm the operator cannot decrypt it, then place the ciphertext in a protected directory writable only by administrators/SYSTEM and readable by the health account.
4. In both the first and a fresh health process, authenticate to the fixed loopback Java endpoint and submit an explicitly unhealthy report. Verify UNHEALTHY_AND_LOCKED, accepted=false and ordersEnabled=false. HTTP redirects/proxies are disabled, timeout is three seconds and response buffering is bounded. No healthy claim or permission to trade is created.
5. Verify unchanged container/image/start time/token and application boot identity, confirm the route stays locked, remove only this run's staging ciphertext and save a custody manifest. Keep encrypted custody for the next collector stage.

DPAPI binds the ciphertext to this Windows identity/profile. It is not protection against an administrator controlling the machine. Future password resets, account deletion or token rotation need a reviewed custody replacement. No production task, collector, VPS modification or rebuild occurs in this batch.

## Spare laptop

Use PowerShell 7 as Administrator. Keep Docker Desktop and the existing MarketBrain application running. Update clean main, then run:

```powershell
& '.\ops\windows\InstallPaytmHealthTokenCustody.ps1'
```

Enter only the existing **Windows marketbrain-health account password** when prompted. No PuTTY, Pageant, SSH passphrase or second window is needed. Do not share passwords or private files.

Expected status: `HEALTH_TOKEN_CUSTODY_PASSED_COLLECTOR_PENDING`. Share the one `paytm-health-token-<run>.json` in `C:\MarketBrainData\Review`. If it fails, retain the report and partial directory for review; do not delete the account or rerun against existing custody. Process diagnostics and the last stage are retained without secret contents.

## Verification and remaining work

43 local checks passed. They cover real CurrentUser DPAPI round trip/tamper rejection, token validation, rejected challenge/receipt contracts, always-unhealthy submission, generated worker execution with fixture identity/storage, fresh-process decryption, failure reporting, no token in outputs and PowerShell parsing. Fresh runspaces test generation without an ambient token, both with and without strict mode. Recovery fixtures reject altered/missing libraries, wrong evidence, existing ciphertext and extra files. HTTP responses and identity are substituted in fixtures; actual spare-account isolation and Java authentication require the runtime report. PowerShell 7 separately reproduces the old missing-variable failure and passes corrected generation with all production dependencies imported.

G3 remains 4/5 (80%); total Paytm readiness remains 14/30 (46.7%). This is a prerequisite within G3.5, not a new completed checkpoint. Next: narrow-token-only clock access and collector provisioning, followed by combined startup/logoff, stale-clock, loss/recovery and no-direct-fallback acceptance. The current Java clock read uses the broader paper-read token, which this batch deliberately does not provision to the health account. G3 reaches 100% only after its final acceptance evidence passes.

## Recovery after the reviewed pre-worker failure

E289 reviews run `3c51b7f72b3342819ab0dd45bbb62897`. Source generation failed before process launch because it still checked the removed `$Token` parameter. The earlier fixtures defined an ambient token and masked that defect. The subsequent `b55631642adb4c95ae17a1d2e3d215f6` run stopped on existing storage without changes.

After updating main, run the same controller with this explicit recovery argument:

```powershell
& '.\ops\windows\InstallPaytmHealthTokenCustody.ps1' `
    -RecoveryReport 'C:\MarketBrainData\Review\paytm-health-token-3c51b7f72b3342819ab0dd45bbb62897.json'
```

The controller verifies the exact reviewed receipt SHA256, account/ACLs, original library hash, library-only directory and absence of staging ciphertext. It rechecks immediately before copying the original library to `library-before-recovery.ps1` without overwrite. Only that verified library is replaced; accounts, keys and existing encrypted secrets are never deleted. Both worker sources are now generated before any installation write. All original token authentication/isolation checks then run and produce one new JSON. Unexpected files or a later partial recovery stop for review rather than resetting state. No rebuild, VPS change or repeat scheduled-signing test is required.
