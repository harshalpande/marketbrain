# Scheduled clock and token verification

E291 accepts this batch in 54.449 seconds. Do not repeat it; continue with [restricted Java clock deployment](paytm-health-clock-deployment.md).

E290 accepts diagnostic health-token custody in 23.732 seconds. Both password-launched health processes authenticated; operator decryption failed as intended, staging ciphertext was removed and the application stayed locked. Fourteen source hashes match 9de6e9d.

The next test verifies the encrypted token under a Task Scheduler Password/Limited logon in session 0. The earlier scheduled clock test did not load a DPAPI token; fresh password-launched process success does not alone prove this logon/profile combination. This combines key signing, real VPS clock reading and local token authentication in one temporary task. It does not install a production collector.

## Procedure and result

- Verify both accepted custody receipts, exact account/SID, key custody and protected token directory. Require the accepted token library hash, custody manifest identity and bounded ciphertext size. No ciphertext or token is copied into evidence.
- Require the existing health batch-logon allow right and unchanged deny policy. Missing rights stop this mode; it does not grant new rights.
- Validate the Windows password with the established fresh-process signing check, then register a disabled, triggerless, non-admin task with a 120-second limit. Verify task ownership/actions/settings before starting it once.
- Worker verifies non-admin SID and session 0, signs twice, reads the pinned VPS clock, decrypts the existing DPAPI ciphertext and authenticates locally. It submits only unhealthy/locked evidence, which grants no health or trading authority. The child clears its token variable; output includes proof flags and application boot ID, never token content.
- Disable and remove the exact owned temporary task on success. Preserve disabled task/evidence for review on failure. Custody, agent keys and application deployment remain unchanged.

## Spare laptop

Use PowerShell 7 as Administrator, with Docker Desktop and MarketBrain running. Update clean main and run:

```powershell
& '.\ops\windows\TestPaytmHealthScheduledAccess.ps1' `
    -TokenReportPath 'C:\MarketBrainData\Review\paytm-health-token-88ebf8fdc3de4c158351e86df95e7217.json'
```

Enter the existing Windows **marketbrain-health** password. No SSH passphrase, PuTTY, Pageant, token import or rebuild is needed. The existing VPS gateway/clock access must be reachable.

Expected: `HEALTH_SCHEDULED_CLOCK_AND_TOKEN_PASSED_COLLECTOR_PENDING`. Share the one `paytm-health-scheduled-<run>.json` printed at the end. On failure preserve evidence and task state before retrying.

## Local verification and progress

23 local scheduled checks pass, including native PS5.1 worker fixtures for success, wrong clock nonce, signing/identity/session failures, token decrypt/authentication failures and secret-free output. Invalid token proof fields and boot IDs are rejected. Existing task-shape/policy checks and native LSA compilation remain covered. No real scheduler, account, policy or network changes were made locally; actual session/profile proof requires the spare report.

G3 remains 4/5 (80%); Paytm readiness remains 14/30 (46.7%). After this account-level acceptance, connect narrow-token Java clock access and the unattended collector, then verify startup/logoff, stale clock, outage/recovery and no direct fallback. No claim of continuous operation, broker login, quotes or trading readiness follows from this one-shot test.
