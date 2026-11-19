# Maintenance automation: initial installation

Priority authorized 2026-11-18. Purpose: remove manual script/report transfer between the development laptop and the spare Windows laptop. This is independent of the MarketBrain application and Paytm transport. Existing trading gates remain unchanged.

## Actual acceptance on 2026-11-18

Diagnostic job `0d38eb91-3c98-4e28-923e-b991f1281a13` passed across the real laptops and VPS; report was read directly from the development laptop. Reviewed runner hash matches, execution 0.065 seconds, approximately 5.59 seconds from queue creation to completion. The interactive user could observe W32Time Running; this does not establish that the separate health account can query synchronization. Intervention job `e31fd9a4-e0bc-4e13-bc5b-1182ecbe95f3` subsequently passed: actual user acknowledged the popup, orders remained disabled, and the agent retrieved the report automatically. Both initial acceptance tests are complete (2/2); this is not full maintenance automation completion.

## Delivered scope and remaining work

### Resume Paytm readiness diagnostics

Follow-up: queued job `9682318f-3121-432a-bf94-54458fefc06e` eventually returned successfully after ISP disruption, but its helper hash was the previous F170 version and it lacked `gatewaySupervisor`. Thus the supervisor inspection is not accepted. Its later capture also recorded stale Windows time data (last sync error 2, age 12035 seconds) and unavailable gateway TCP. A transport cancellation exception was a connection-attempt timeout, not cancellation of that queued job.

The updater now matches quoted/unquoted `-File` arguments case-insensitively, checks the process owner/creation time, acquires the worker mutex before replacement, and requires a fresh process ID, random startup nonce and both loaded source hashes before printing `RUNNER_UPDATE_VERIFIED`. The runner reports its startup-captured hashes rather than later disk contents, and clears historical connection errors after successful polling. Run the updater as the same Windows user and elevation as the existing worker (the latest report shows it is elevated). Pairing is preserved. Real Windows fixture replacement with an unquoted command line passed; actual spare replacement still needs confirmation.

The supervisor inspection extension also reads six fixed JSON snapshots: manifest, host control, transport control, heartbeat, blocked marker and original startup failure. It returns only allowlisted status/error fields, preserves access/missing/size failures, observes a second heartbeat, queries the one named supervisor task with a 12-second child-process limit, and reads SSH-agent service state. It never starts/enables the task or clears a latch. Raw logs, credentials, key files and arbitrary JSON properties are not uploaded. The same `Update-AutomationDiagnostics.ps1` installs this helper extension and backs up both installed files; pairing/VPS configuration remain unchanged. Runner self-update is not implemented, so this helper update still requires a local command. After the update, the agent can run the complete read-only inspection and collect its report automatically.

The next runner version extends the existing `diagnostic` job with fixed read-only observations: operator elevation flag, W32Time status/source command exit codes and bounded output, loopback 18889 listener/TCP state, and two verified HEAD probes through that proxy to the fixed Paytm developer root. Probe connect timeouts of two and eight seconds are a diagnostic comparison; production health thresholds remain unchanged. The result includes runner and helper source hashes. A successful collection means evidence was captured, not that Paytm readiness passed. HTTP 503 is transport evidence only.

This runs under the signed-in operator, **not** the dedicated health account. Its findings must be compared with the established health-account access denial; they cannot close that gate. No broker credentials, login, quote fetch, orders, policy changes or administrative permissions are requested. The two bounded network probes are the only provider contact added.

On the spare laptop in PowerShell 7, fast-forward the clean main checkout, then run:

```powershell
& .\ops\automation\Update-AutomationDiagnostics.ps1
```

The update validates the old runner hash, refuses pending work, stops only the identified same-user installed runner, preserves a backup and pairing, installs the diagnostic helper and new runner, and starts it again. Any claim racing with the stop remains preserved and is marked interrupted rather than repeated. No VPS change. Tell the agent when the update completes; it can submit `Send-AutomationJob.ps1 -Kind diagnostic` from the development laptop and read the returned report directly.

The existing administrator-only scheduled health test still requires a local password. It is not launched by this job. We will use the new evidence to choose the narrow correction before adapting that privileged test; blindly rerunning the known failing collector would not resolve the cause.

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

### Repair permission denied on first start

2026-11-18 VPS journal establishes repeated `can't open file '/opt/marketbrain-automation/relay.py': [Errno 13] Permission denied`, with no 18443 listener. The launcher sets umask 077; the original installer requested directory mode 0755 but did not chmod it afterwards, leaving 0700. This is an installer defect, not a pairing failure. The original transient systemctl active check also failed to establish real readiness.

After pulling the corrected repository, run `ops/automation/Copy-RelayPermissionRepair.ps1` from PowerShell 7. In verified administrator PuTTY run `sudo -v`, then paste the copied command. It verifies root-owned, non-symlink program paths and the service identity, stops only the automation service, sets the public code directory to 0755 and program to 0644, checks read-but-not-write access under the actual relay account, restarts and probes TLS plus unauthenticated HTTP denial. It does not change secret-state permissions, tokens, certificates, database, SSH, firewall or Paytm gateway. Expected markers: `SERVICE_CODE_READ_OK_NOT_WRITABLE`, `RELAY_TLS_READY_AUTHENTICATION_REQUIRED`, `REPAIR_COMPLETE`.

Do not rerun initialization. Retry controller diagnostic submission with existing ID `0d38eb91-3c98-4e28-923e-b991f1281a13` once readiness passes. An office-proxy restriction may remain independently; if so, test from the spare laptop before modifying network settings. The repair is prepared locally; actual Linux service recovery needs the VPS output. Local WSL execution was unavailable (logon-type restriction); no Linux execution is claimed.

- Connection failure: runner retains `pending.json` locally and retries delivery. Terminal results are immutable and re-upload is idempotent. Failed jobs are not rerun automatically.
- Runner interruption: a saved running job becomes `INTERRUPTED` on restart; it is never silently repeated. Repeated claims return the same active ID, so a lost claim response does not strand the queue.
- Controller disconnect: `last-request.json` contains the ID before submission. Resume with `Send-AutomationJob.ps1 -ReadOnly -JobId '<saved-id>'`; if submission never reached the relay, resubmit using the **same ID and kind**.
- Cancel a queued job: `Send-AutomationJob.ps1 -Cancel -JobId '<id>'`. Running work is not force-killed remotely in this version; the user can cancel the local intervention prompt. Its timeout is five minutes.
- Pause runner: sign out, or identify and stop only the `pwsh.exe` process whose command line names the installed `Start-AutomationWorker.ps1`. Do not kill unrelated PowerShell/gateway processes. Delete only the `MarketBrain Automation.lnk` Startup shortcut to prevent the next sign-in launch; preserve reports and pairing files.
- Relay stop: `sudo systemctl stop marketbrain-automation.service`. This does not stop the Paytm gateway.
- Relay retains at most 10,000 job records and at most 20 outstanding jobs; bodies are limited to 256 KiB. No automatic history deletion. Archive/review before capacity is reached. Local reports and the VPS SQLite database need a retention policy before a broad job catalogue is enabled.
- Do not rotate credentials or remove state to resolve a failed job; preserve the evidence.

## Verification and rollout gates

Local checks cover queue persistence, duplicate requests, lost claim responses, interruption state, immutable results, cancellation, unsupported job rejection, real HTTPS and Windows DPAPI, actual diagnostic worker execution, wrong-certificate rejection, wrong-token rejection and role separation. The Linux systemd installer and actual cross-machine networking require installation acceptance; they are not proven by local fixtures. The actual intervention popup and diagnostic acceptance above passed on 2026-11-18. Linux service recovery and end-to-end availability are established for these runs, not long-term uptime or restart resilience.

Next, after those two jobs pass: adapt the existing Paytm health diagnostic into a fixed catalogue entry with a bounded output schema; introduce explicit local password/elevation handling; then add background signed-out operation, reviewed release updates and lifecycle acceptance. Existing `Read-Host`, clipboard/PuTTY interactions and administrator requirements must be adapted explicitly, not piped blindly into a background process. Automatic analysis and code changes still require an active agent session; queue execution/result collection can operate without one.

## Latest Paytm evidence, kept separate

Report `paytm-health-scheduled-3f20293aade542e7985c9055f2c2a79a.json` proves all three background collector rounds received W32Time access-denied `0x80070005`, and curl exit 28 after approximately two seconds. SSH signing, VPS clock and application token authentication passed; final health revoked, application locked, failed temporary task disabled. The timeout's underlying network cause is not yet established. Do not change clock thresholds or grant administrator privileges based solely on this evidence. G3 remains **4/5 (80%)**; Paytm readiness **14/30 (46.7%)**. Automation implementation does not close a Paytm checkpoint.

## First automated Paytm observation

Job `c4a87628-9559-4070-9d41-79d535a16b2f` returned automatically on 2026-11-18, in 10.866 seconds execution. Runner/helper hashes verified. This runner was elevated (`elevated: true`); W32Time status/source queries passed with sync age 1753 seconds. These results cannot establish permission under the dedicated health identity. Local TCP 18889 was unreachable; curl returned exit 28 with the 2-second limit and exit 7 (failed connection) with the 8-second limit. Listener inspection reported CimJobException, so do not claim a confirmed empty listener table. No successful TCP or proxy CONNECT/TLS stage occurred. Next inspect the supervisor task/status and existing failure latch before any restart. No automatic route rearm, permission change or health acceptance.

## Verified supervisor capture

Job `53b2fb40-6dab-4d70-b16e-9002e7b9d957` returned the expected runner/helper hashes and supervisor section. Original startup and blocked markers record HOST_AGENT_UNAVAILABLE for instance 1eef65f6e872480ebd5acfa4d361261d; heartbeat sequence 12161 remained unchanged at 2026-11-16T10:21:04.7748113Z. Host control LOCKED, transport ENABLED. Current SSH-agent service is Running/Automatic; gateway account access is not established by this. The scheduled-task query timed out after 12 seconds; no current task state was obtained. Elevated W32Time now reports last error 0 and age about 599 seconds. No controls/latches were changed. Next needs alternate bounded native task inspection and exact-account signing proof before recovery.

## Password-dependent signing with automatic result return

The automatic retry `2a9b8a58-550e-449d-9350-85c825210e8a` resolved the task-query timeout: task enabled, Ready (idle), last result 1. The historical HOST_AGENT_UNAVAILABLE latch and blocked heartbeat remain. Elevated operator time access is not health-account acceptance.

Run the following in elevated PowerShell 7 on the spare laptop after pulling the reviewed commit:

```powershell
& .\ops\automation\Update-AutomationDiagnostics.ps1
& .\ops\automation\Invoke-LocalGatewaySigning.ps1
```

The existing isolated scheduled signing test asks for `TEST-SCHEDULED-KEY`, then the Windows `marketbrain-gateway` account password locally. It verifies signing under the exact non-administrator, noninteractive identity. It does not import keys, change the agent, restart the supervisor or contact the broker. Success removes the temporary task; failure disables and preserves it for review. Do not rerun failed tests automatically.

The wrapper preserves the original report and atomically publishes a bounded completed copy at `C:\MarketBrainData\Review\automation-gateway-signing-latest.json`. It checks production control/status file hashes before and after. The next automated diagnostic returns allowlisted status, worker checks, bounded native classifications and source hashes, excluding raw logs, keys, passwords and unknown fields. A missing or stale report cannot establish acceptance; match run identity, source hashes and the current local completion.

Tell the agent when the local prompt finishes; no report upload is required. The runner currently accepts only diagnostic and intervention-test jobs: launching this password-dependent test and updating the installed helper still require this local command. This is not unattended signing deployment. A successful signing receipt's legacy status mentions supervisor installation pending; it does not authorize reinstalling an existing supervisor. Review current evidence before preparing recovery.

Acceptance on 2026-11-18: job `9a663296-a5f5-40d3-aadc-e6774c047358` automatically returned signing run `adafbbe28dac485e95cb2ebc75768ccf`. Two signatures passed under non-admin session 0, native operations exited zero, temporary task removed, production state unchanged. Eight source hashes verified with Windows CRLF normalization as needed. Gateway recovery has not run; the current saved failure and idle task remain.

## Current gateway recovery after signing acceptance

Prepared on 2026-11-18; spare-machine runtime acceptance pending. `Invoke-LocalGatewayRecovery.ps1` invokes `RepairPaytmNativeProcess.ps1 -CurrentSigningRecovery` in a separate PowerShell process. The adapter accepts only signing run `adafbbe28dac485e95cb2ebc75768ccf` with the six reviewed source hashes and complete signing/task-cleanup proof. It requires the existing owned task idle with last exit 1, application locked and broker disabled, and saved failure instance `1eef65f6e872480ebd5acfa4d361261d` at heartbeat 12161.

With installer and worker locks held, verify installed code and empty transport listener, snapshot/recheck files and task state, archive and hash-check existing evidence, then clear only the three reviewed incident markers. Preserve any session checkpoint. Start the existing task once; require a fresh worker and advancing transport heartbeat. Reuse the existing 30-minute stability observation and initial/final application route checks. Failure stops/disables the owned task and preserves evidence. No code/key/credential replacement, VPS changes or broker orders.

On the spare laptop, run elevated PowerShell 7 after a clean fast-forward pull:

```powershell
& .\ops\automation\Update-AutomationDiagnostics.ps1
& .\ops\automation\Invoke-LocalGatewayRecovery.ps1
```

Keep Docker Desktop and the existing MarketBrain application running, and leave this window open for approximately 30-35 minutes. No PuTTY or password prompt is expected. One local launch is still required: the deployed relay does not yet expose recovery jobs. The wrapper publishes its bounded result to `C:\MarketBrainData\Review\automation-gateway-recovery-latest.json`; the next diagnostic returns sanitized status, recovery, stability and cleanup fields automatically. Do not rerun on failure. A successful test restores transport evidence; it does not close the separate health-account time-query or durable collector gates.

Local verification: 42 archive/start/drift assertions, 15 receipt/incident rejection cases, 47 existing controller failure/cleanup assertions across eight mocked workflows, and automated snapshot filtering. These fixtures do not claim a real spare-machine recovery or a real 30-minute soak.

## Resume after application health block

The 2026-11-18 recovery did restore the gateway: one new worker, advancing heartbeat, proxy CONNECT 200, TLS verification code 0 and HTTP 503 from the root endpoint. Root HTTP 503 does not establish broker readiness. The controller then incorrectly required application route arming before the separate health collector was ready. Application TIMING_BLOCKED/HEALTH_UNCONFIRMED was correct; controller sequencing was defective. No 30-minute stability credit was earned.

Cleanup and automatic diagnostic `cd8b3936-dbd4-45f5-95bc-68d27e0c4bcd` establish task Disabled, last result 0, STOP control, STOPPED instance `117f5ad1df7344828ea88cc3c00a9d3a`, sequence 11, with no new failure marker. The original recovery command must not be rerun against this changed state.

The resume adapter pins the exact completed recovery receipt SHA256 and verifies the current owned disabled task, stopped instance, controls and empty listener. It archives current state without deleting markers or checkpoints, enables/starts the existing task once, and uses the unchanged 30-minute transport observation. Before and after, application status/head must remain LOCKED with no outbound diagnostic request; the paper writer remains locked. It never calls arm or weakens timing/health checks. Failure retains the established stop/disable cleanup.

After pulling, run elevated PowerShell 7 on the spare laptop with Docker and MarketBrain running:

```powershell
& .\ops\automation\Update-AutomationDiagnostics.ps1
& .\ops\automation\Invoke-LocalGatewayRecovery.ps1 -ResumeAfterHealthBlock
```

Expected success is `TRANSPORT_STABILITY_PASSED_APPLICATION_HEALTH_PENDING`. This is transport-only acceptance, not authenticated broker/application readiness. Automatic result return is retained; no file upload is required. Leave the window open for 30-35 minutes; do not retry a failure. Local tests cover 29 resume/archive/start assertions and 48 controller assertions over eight mocked success/failure workflows; real spare runtime remains pending.

Transport-only acceptance, 2026-11-18: recovery `cad6485c136b461c85a1fe71a7e59be0` completed 149 observations over 1811.422 seconds with the same worker, no reported transport failures, preserved account and locked application. Automatic job `5ef8d851-9b45-44dc-a4fc-a65b3106b7de` subsequently confirmed Running task, heartbeat 3935 to 3938, TCP success and both proxy probes exiting 0 (CONNECT 200; root HTTP 503). All reported source hashes verified with Windows line endings where applicable.

This closes the current transport-recovery incident, not G3.5. Health-account Windows time query permissions, scheduled collector and lifecycle remain pending. The deployed catalogue still contains diagnostic and intervention-test only; no arbitrary script execution or remote health-account password submission is available. The current health scheduled test requires a local password and must be adapted before claiming unattended execution. No recovery rerun is required after this acceptance.

## Bounded controller observation batches

`Start-AutomationDiagnosticBatch.ps1` runs on the development controller for 30-45 minutes. It submits one diagnostic at a time, retains the job ID before submission, retries the same idempotent submission after a lost reply, and saves each raw result plus a separate assessment. Default spacing is 120 seconds after completion. Job failure does not create a repair action or grant readiness: the assessment records transport failures, missing elevation, inaccessible supervisor state and unconfirmed Windows synchronization separately. The batch has no arbitrary-command, account-password, gateway-reset or clock-change capability.

The active agent reviews results and chooses any subsequent authorized implementation. Existing catalogue is diagnostic/intervention-test only. Automatically executing new repair scripts requires a reviewed runner/catalogue deployment; this batch does not bypass that boundary. At window end, a queued/running job is preserved by ID and must be fetched rather than resubmitted under a new ID.

Post-restart observation on 2026-11-19: initial runner was non-elevated. Operator status query returned sync error 2; source query was access denied. The first TCP/TLS probes passed, the next found port 18889 unavailable. Protected gateway files were unreadable, so cause could not be established from that context. Microsoft documents local administrator membership for w32tm: https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings . The dedicated non-admin collector must not assume those queries are available. Elevating an operator diagnostic does not prove collector readiness.

Tests cover eight semantic assessment cases and simulated lost-reply/idempotent submission, sequential continuation after failure, bounded window and retained raw results. Simulated timing is not a runtime stability acceptance.
