# E257: current clock mismatch follow-up

**Current E257, 2026-11-15:** Clock collection completed with findings, not acceptance: VPS16.188-17.325s ahead of Windows; Java relative to Windows -0.030 to+0.033s. All10 samples collected, VPS NTP yes5/5, six source hashes matchca02d27 CRLF, unchanged container and key cleanup confirmed. [Next: fresh read-only Windows Time access diagnosis](paytm-clock-drift-followup.md). Historical SERVICE_START denial is not assumed current. G3.5 blocked;14/30 (46.7%), unchanged.

Earlier instructions below are historical; use the follow-up linked above.

# Fresh three-clock snapshot after runtime recovery

E256, November15,2026. G3.2 is complete. The prior clock snapshot E166 is several weeks old and does not establish current alignment. Reuse the existing read-only collector, now recording six source hashes. No restart, deployment, clock setting, key import into the gateway, broker login or trade.

## Why this check

Five paired observations compare Windows with VPS UTC (pinned SSH host) and the actual Java account-read timestamp. Bounds include round-trip delay and wall/monotonic discrepancy; VPS NTPSynchronized must report yes. The existing five-second screen is diagnostic only, not the trading tolerance or proof of absolute UTC accuracy. A pass informs the remaining G3.5 policy acceptance; it does not close G3.5 automatically. Long-term drift, automatic Windows synchronization and future quote-age enforcement remain distinct.

## Steps on the spare laptop

1. Keep Docker/the existing application container running, jobs idle, and time settings unchanged.
2. Open Pageant. Load the original encrypted **administrator PPK for marketbrain-admin**, not the marketbrain-gateway key. Enter its passphrase only in Pageant. No PuTTY terminal is needed. Never share the key or passphrase.
3. Open elevated PowerShell7, pull main and run:

```powershell
& '.\ops\windows\TestPaytmClockSnapshot.ps1'
```

4. At the prompt, type `CLOCK-CHECK` only once the administrator key is available in Pageant. The script queries the VPS and Java five times each.
5. At the final prompt, remove the administrator key from Pageant if you loaded it only for this check. Leave unrelated keys needed by active sessions alone and keep the encrypted PPK file. Then type `KEY-REVIEWED`.
6. Share the single printed `paytm-clock-snapshot-*.json` regardless of status. Normally1-2 minutes plus key-loading time.

Expected clean screen: `CLOCK_SNAPSHOT_WITHIN_SCREEN_RELEASE_PENDING`. Findings are captured as `CLOCK_SNAPSHOT_CAPTURED_WITH_FINDINGS`; do not change clocks during collection. There is no need to repeat gateway latch, sign-out or shutdown testing.

## Local verification

113 comparison/runner assertions (ten mocked workflows) and28 HTTP boundary assertions pass. The collector now includes source hashes for review; comparison thresholds and behavior are unchanged. Current Paytm readiness14/30 (46.7%); G3=80%. Login, quotes and Telegram remain pending.
