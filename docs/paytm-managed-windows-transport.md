# Managed Windows transport and application-route batch

E211, 2026-11-03. Implementation and local verification complete; spare acceptance pending. E207 Windows account/task/signing and E210 VPS lifecycle remain accepted. Do not repeat provisioning, key import, the VPS installer or report recovery.

## Purpose and scope

The existing scheduled task currently signs and monitors in LOCKED mode. This extension lets that same non-admin, session-0 worker own the SSH connection from Windows `127.0.0.1:18889` to the accepted VPS loopback proxy `127.0.0.1:18888`. The existing Java diagnostic route is then tested through that connection. The task identity, stored password, key custody, VPS configuration and application container are retained.

This is transport readiness. A certificate-validated root HEAD response, including HTTP 503, does not establish Paytm authentication, quote availability or order readiness. The application route and paper writer finish LOCKED. No broker credential, order, reservation or fill is enabled.

## One combined verification run

1. Check accepted receipts, account/custody, installed source hashes, protected paths, task ownership and advancing LOCKED heartbeat. Inspect the existing application and recorded account without rebuilding it.
2. Compile the native extension in protected staging. Stop the owned worker, acquire its exclusive lease and verify backups of runner, manifest and STOP control before replacement.
3. Start with transport DISABLED, then explicitly enable. Verify exact-agent signing, pinned SSH host, effective client configuration, sole owned IPv4 loopback listener, TLS and destination/protocol denials.
4. Exercise the existing Java route. Duplicate task start must preserve the same worker and SSH child. Disable must close the listener and make the armed application route fail closed.
5. Re-enable and require explicit application rearm. Kill only the verified SSH child (PID, birth time and executable), then observe automatic backoff/reconnect. Reconnect must not rearm the application.
6. STOP, start again under persistent STOP, then explicitly start the worker again. STOP must suppress signing/network contact. Verify another application TLS request, then lock the route and confirm unchanged container/image/start time, writer lock and account/ledger/history.

The worker uses monotonic deadlines, bounded output, a kill-on-close Windows job and capped reconnect delays. Host-key/authentication/listener/configuration/TLS failures block retries. Known transient transport failures reconnect. Connection health is checked every ten seconds; root HTTP status is recorded separately from TLS success. Curl CONNECT-denial variants 7/56 require a recorded proxy 403, not just an error code.

Success leaves managed transport running and the existing startup task enabled, while application authority remains locked. Cold boot, logoff, real network interruption and the remaining installed-system security/clock cases are later G2/G3 acceptance work; local fixtures do not prove those behaviors on the spare laptop.

## Run on the spare laptop

Use a **fresh PowerShell 7 window as Administrator**. Keep Docker Desktop and the existing MarketBrain application running. Close any old manual gateway tunnel; no PuTTY or Pageant operation is needed for this batch. Do not remove the Windows agent key. Leave the accepted receipts in `C:\MarketBrainData\Review`.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 as Administrator.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this PowerShell 7 window as Administrator.'
}

Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if ($changes.Count) { throw 'Working tree has changes. Preserve them before updating.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }

& '.\ops\windows\InstallPaytmManagedTransport.ps1'
```

Expect several minutes, with stage progress and bounded waits. Share only the printed `paytm-managed-transport-*.json`. Success is:

```text
MANAGED_WINDOWS_TRANSPORT_AND_APPLICATION_ROUTE_PASSED_BOOT_PENDING
```

No passwords or private-key paths are requested. No Docker rebuild/restart or VPS command is required. If a preflight fails, the extension is not installed. If failure occurs after the owned worker is stopped for upgrade, the script requests persistent STOP, disables only its task, and verifies task shutdown and a free tunnel port. Any failure of that cleanup is explicitly reported. Backups and partial evidence remain; do not blindly rerun the installer or delete the account/key.

To deliberately stop the managed transport later, in the same elevated repository window:

```powershell
& '.\ops\windows\StopPaytmGatewaySupervisor.ps1'
```

This disables the task and leaves STOP persistent; restarting is a separate reviewed operation, not an automatic installer replay.

## Evidence and progress

[Local verification](evidence/paytm-managed-transport-local-20261103.json) separates actual native process/loopback/Windows-curl and bootstrap tests from mocked task, signing, remote network and application workflows. No spare/VPS deployment was performed from the development machine.

Accepted group percentages remain **G1 100%, G2 60%, G3 0%, G4 0%, G5 0%, G6 0%**: 8/30 equal-weight checkpoints, not effort estimates. This batch prepares the remaining G2 effective-route evidence and parts of G3, but closes no runtime checkpoint before report review. After acceptance, consolidate the remaining real recovery/boot tests, then login, fresh quotes and the combined Telegram ACCEPT/REJECT/expiry batch. Live execution remains a separate later gate.
