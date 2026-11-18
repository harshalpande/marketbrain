# Maintenance automation: initial installation

Priority authorized 2026-11-18. Purpose: remove manual script/report transfer between the development laptop and the spare Windows laptop. This is independent of the MarketBrain application and Paytm transport. Existing trading gates remain unchanged.

## Delivered scope and remaining work

This first release supports two fixed jobs: `diagnostic` (Windows time-service status and runner identity; read-only) and `intervention-test` (local confirmation popup with a five-minute timeout). It does not yet execute the existing Paytm installer catalogue, accept arbitrary PowerShell, update itself, collect passwords, run elevated jobs, or run while the Windows user is signed out. Do not describe this as full maintenance automation acceptance.

The Windows runner starts at sign-in, continues while the user is signed in, and polls every ten seconds. An HTTPS relay on the existing VPS holds jobs and results. Both laptops connect outbound. No incoming laptop port, router change, SMTP, or trading-application endpoint is required. The controller is callable from the agent's workspace after pairing, so the user need not submit later supported jobs manually.

The setup uses TCP **18443** on the VPS. The installer leaves existing SSH, Paytm proxy and firewall configuration unchanged. If the host/provider firewall blocks that port, connectivity must be resolved before pairing acceptance; do not disable the firewall. Office device policies still apply. No new provider subscription is introduced, but the VPS's existing billing and network allowance remain applicable.

TLS uses a generated one-year certificate whose SHA-256 fingerprint is pinned during pairing through the already verified SSH session. Clients also enforce certificate validity dates. Renewal/re-pairing is required before expiry. Two independent random credentials separate controller submission/results from worker claim/completion. The relay stores only credential hashes; Windows protects client credentials with current-user DPAPI. Neither credentials nor pairing lines belong in chat, Git, screenshots or diagnostics. Jobs/results on VPS are protected by filesystem permissions, not encrypted at rest; only the small, fixed diagnostic schema is sent in this release.

## One-time steps

Use **PowerShell 7**, as the ordinary Windows user who will remain signed in. There is no need to elevate the Windows runner. Run the normal clean `main` fast-forward pull on both laptops first. Do not discard local changes.

On the laptop with the verified administrator PuTTY session:

```powershell
& .\ops\automation\Copy-RelayInstaller.ps1
```

In PuTTY, run `sudo -v` and enter the administrator password. Then paste the copied installer. It installs a separate non-login `marketbrain-relay` account, a small Python service, state directory and certificate. It refuses existing installation paths/accounts or an occupied port, rather than overwriting partial state. A failed setup must be inspected before retrying. Python 3 and OpenSSL must already exist.

The VPS prints **two private pairing lines** once. Keep this PuTTY window open until both laptops are paired. Do not paste these lines into the AI conversation. If a line is lost, stop and arrange credential rotation; repeated installation is not recovery.

On the **development laptop**, run:

```powershell
& .\ops\automation\Initialize-Automation.ps1 -Role controller
```

Paste only the complete `CONTROLLER_PAIRING=...` line into its hidden prompt. On the **spare laptop**, run:

```powershell
& .\ops\automation\Initialize-Automation.ps1 -Role worker
# Paste only WORKER_PAIRING=... into the hidden prompt.
& .\ops\automation\Install-AutomationStartup.ps1
```

The worker runs from `%LOCALAPPDATA%\MarketBrainAutomation\runner`, independent of the working checkout. A per-user Startup shortcut restarts it at sign-in. Keep this user signed in. Unlock the desktop to respond to prompts. Do not put credentials into environment variables or command arguments.

On the **development laptop**, run the combined acceptance sequence:

```powershell
& .\ops\automation\Send-AutomationJob.ps1 -Kind diagnostic
& .\ops\automation\Send-AutomationJob.ps1 -Kind intervention-test
```

The first report should return automatically. For the second, click OK in the MarketBrain popup **on the spare laptop**. The development terminal displays `WAITING_FOR_USER` then `SUCCEEDED`. Reports are automatically saved on the development laptop under `%LOCALAPPDATA%\MarketBrainAutomation\reports`. The active agent can read those files locally: no manual upload is needed.

## Recovery, controls and retention

- Connection failure: runner retains `pending.json` locally and retries delivery. Terminal results are immutable and re-upload is idempotent. Failed jobs are not rerun automatically.
- Runner interruption: a saved running job becomes `INTERRUPTED` on restart; it is never silently repeated. Repeated claims return the same active ID, so a lost claim response does not strand the queue.
- Controller disconnect: `last-request.json` contains the ID before submission. Resume with `Send-AutomationJob.ps1 -ReadOnly -JobId '<saved-id>'`; if submission never reached the relay, resubmit using the **same ID and kind**.
- Cancel a queued job: `Send-AutomationJob.ps1 -Cancel -JobId '<id>'`. Running work is not force-killed remotely in this version; the user can cancel the local intervention prompt. Its timeout is five minutes.
- Pause runner: sign out, or identify and stop only the `pwsh.exe` process whose command line names the installed `Start-AutomationWorker.ps1`. Do not kill unrelated PowerShell/gateway processes. Delete only the `MarketBrain Automation.lnk` Startup shortcut to prevent the next sign-in launch; preserve reports and pairing files.
- Relay stop: `sudo systemctl stop marketbrain-automation.service`. This does not stop the Paytm gateway.
- Relay retains at most 10,000 job records and at most 20 outstanding jobs; bodies are limited to 256 KiB. No automatic history deletion. Archive/review before capacity is reached. Local reports and the VPS SQLite database need a retention policy before a broad job catalogue is enabled.
- Do not rotate credentials or remove state to resolve a failed job; preserve the evidence.

## Verification and rollout gates

Local checks cover queue persistence, duplicate requests, lost claim responses, interruption state, immutable results, cancellation, unsupported job rejection, real HTTPS and Windows DPAPI, actual diagnostic worker execution, wrong-certificate rejection, wrong-token rejection and role separation. The Linux systemd installer and actual cross-machine networking require installation acceptance; they are not proven by local fixtures. The intervention popup requires the user acceptance above.

Next, after those two jobs pass: adapt the existing Paytm health diagnostic into a fixed catalogue entry with a bounded output schema; introduce explicit local password/elevation handling; then add background signed-out operation, reviewed release updates and lifecycle acceptance. Existing `Read-Host`, clipboard/PuTTY interactions and administrator requirements must be adapted explicitly, not piped blindly into a background process. Automatic analysis and code changes still require an active agent session; queue execution/result collection can operate without one.

## Latest Paytm evidence, kept separate

Report `paytm-health-scheduled-3f20293aade542e7985c9055f2c2a79a.json` proves all three background collector rounds received W32Time access-denied `0x80070005`, and curl exit 28 after approximately two seconds. SSH signing, VPS clock and application token authentication passed; final health revoked, application locked, failed temporary task disabled. The timeout's underlying network cause is not yet established. Do not change clock thresholds or grant administrator privileges based solely on this evidence. G3 remains **4/5 (80%)**; Paytm readiness **14/30 (46.7%)**. Automation implementation does not close a Paytm checkpoint.
