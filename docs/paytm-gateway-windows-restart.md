# Gateway verification across a Windows restart

2026-11-03, E213/E214. Managed Windows transport and all four application-route checks are accepted from run `8ac7cdda3ca7475eb001df485797cb70` in 64.115 seconds. G2.5 is complete; G2 is now **80%**. Do not rerun installation, key import or the VPS lifecycle test.

## What this next batch establishes

The existing scheduled task should start its non-admin worker automatically after Windows restarts, use the retained agent key, restore its pinned SSH connection and pass TLS/denial checks. The collector observes the task; it never starts, enables or restarts it. The installed startup trigger/settings are validated, and the owner explicitly confirms no manual gateway start.

The Before phase records a fresh worker heartbeat, installed hashes, machine hash, Windows boot time, account and locked application state in an administrator-protected checkpoint. After checks a newer Windows boot, a different worker instance that started before collection, corresponding task start time, unchanged installation, advancing heartbeat and owned listener. It also verifies a fresh application boot ID, unchanged container/image/account, locked paper writer and credential-free application TLS routing. The final application route is locked.

This proves the observed Windows restart scenario, not an independent sign-out-only test, full power-loss/cold-boot scenario or accurate UTC synchronization. Docker Desktop may need to be opened after login, and the existing MarketBrain application may need to be started manually. Those actions are separate from unattended gateway startup; do not claim unattended application startup from this test.

## Before restarting

Use PowerShell 7 as Administrator. Keep Docker Desktop and the existing MarketBrain service running. Keep the accepted transport JSON at its original `C:\MarketBrainData\Review` path.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Preserve local changes before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmGatewayRestart.ps1' -Phase Before
```

Proceed only after `BASELINE_SAVED_AWAITING_WINDOWS_RESTART`. The checkpoint and report path are saved; no token or report filename needs to be remembered. A failed Before phase does not request a restart.

## Restart and verify

1. Save open work. Use **Start > Power > Restart** on the spare laptop. Do not restart the VPS.
2. Sign back in and wait at least **90 seconds**. Do not open a manual tunnel, load Pageant keys, start the gateway scheduled task or run the transport installer.
3. Open Docker Desktop if needed. If the existing `marketbrain-service` is stopped, start that existing container and wait for it to remain Running/Healthy. Do not recreate it.
4. Open a fresh PowerShell 7 window as Administrator and run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
& '.\ops\windows\TestPaytmGatewayRestart.ps1' `
    -Phase After -ConfirmNoManualGatewayStart
```

`-ConfirmNoManualGatewayStart` records your confirmation that you did not manually start the gateway or its task after restarting Windows. It is owner evidence, not a substitute for the observed task/process/boot checks.

Expected final status: `WINDOWS_RESTART_TRANSPORT_AND_APPLICATION_ROUTE_PASSED`. Share the **one `paytm-gateway-restart-*.json` file** printed by the script. After updates the same report as Before. On failure, share that report; the protected baseline remains available for an After-only follow-up. Do not repeat Before, reinstall, clear failure latches or manually start the gateway to make the test pass.

## Safety, progress and limitations

The collector writes its own checkpoint/report and temporarily arms the existing restricted HEAD diagnostic only in After. It does not modify task settings, controls, keys, VPS, Docker deployment, firewall or database. Existing runtime behavior remains active while it collects. Paytm credentials and orders remain disabled; account and writer checks remain mandatory. Report failure does not stop an already accepted gateway merely because a read-only collector failed.

Local verification: [66 assertions across rules and seven two-phase workflows](evidence/paytm-gateway-restart-local-20261103.json), with runtime APIs substituted. The actual supplied report was also validated independently. No spare restart has been inferred from local tests.

Accepted checkpoints are **G1 100%, G2 80%, G3 0%, G4 0%, G5 0%, G6 0%** (9/30 equal-weight checkpoints). Successful runtime startup evidence is needed to close G2.4; no advance is recorded before reviewing the After report. Remaining G3 network/security/clock/cancellation and separate logoff/cold-boot acceptance still precede full unattended readiness. Login, fresh quotes and Telegram review-only ACCEPT/REJECT/expiry follow those gates.
