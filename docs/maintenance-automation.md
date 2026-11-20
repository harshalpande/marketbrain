# Maintenance automation: initial installation

**2026-11-20: automated health-account probe prepared; local credential step required.** [Evidence](evidence/time-account-probe-preparation-20261120.json). Queue submitted diagnostics, captured failures and retrieved reports without manual transfer. Password-free cross-account S4U registration was rejected with Access denied; Microsoft requires the target password. That approach is withdrawn. `TestPaytmTimeAccountAccess.ps1` now accepts the existing health password locally, creates one limited Password-logon task, checks three fresh reads and write denials, removes its task and saves a protected report for automatic Observe collection. No account elevation or credential transport. A possible snapshot replacement lookup race has bounded I/O retries; policy/identity/stale failures never retry. Tests: ten result cases, four isolated workflows, three retry cases, generated PS5 worker, PS5/PS7 parity; 25 existing Java login/callback/Telegram tests passed. Actual health-account access/publication/lifecycle remain pending. G1/G2 100%, G3 80%, G4/G5/G6 0%;14/30 (46.7%).


**2026-11-20: SYSTEM time observer accepted through automation.** [Runtime evidence](evidence/time-observer-runtime-20261120.json). Diagnostic and catalogue verified; Observe found no installation. First Apply stopped on PowerShell 7 JSON conversion of the ISO boot identifier to DateTime. PS5/PS7 regression now preserves the exact string. Read-only inspection confirmed matching boot/frequency, expected worker hash and disabled task. Guarded recovery verified the existing worker/task before one start; job0a5d1c49-ca5c-4d28-9eaf-b7d87aaf3c95 passed in9.488s with sequences1->2 and snapshot age1.295s. SYSTEM observer remains running; no account elevation, broker credentials or orders. No manual script/result transfer after bootstrap. Next: actual non-admin scheduled collector access, health publication/revocation and observer lifecycle acceptance. G3 remains80%; Paytm readiness14/30 (46.7%), not whole-project completion.


**2026-11-20: Windows time observer implementation prepared.** [Design and activation](paytm-time-observer.md). Scheduled collector cannot call administrator-only w32tm; keep its non-admin identity and use a separate fixed SYSTEM read-only observer. Protected snapshots have monotonic freshness, boot identity, bounded size and write-ACL checks. Collector retains clock/TLS/deadline/revocation rules. New queued capability paytm-time-observer requires one relay/runner catalogue update; no installation or account permission change has occurred remotely. System snapshot acceptance and actual health-account acceptance are separate. Local protocol/ACL/install/collector tests passed; runtime and G3.5 remain pending. G3 80%, total14/30 (46.7%).


**2026-11-20: queued post-recovery observation accepted.** [Runtime evidence](evidence/post-recovery-observation-20261120.json): job74359b55-8a46-455c-88f2-d5b157eaa846, reviewed source hash matched, one start, 46 ready samples and nine distinct TLS observations over a 94.451-second observation window including startup; required90 continuous ready seconds passed. Total job104.182s. Local actuator200/UP; stop/disable and guard cleanup verified, no credentials or orders. Earlier attempt stopped on status-read IOException after44.233s; controller now uses delete-sharing and bounded replacement-error retries. Local stress test passed300 reads with250 atomic replacements plus size and lock bounds. No installed gateway code change in this follow-up. [Historical health-account report](evidence/health-account-blocker-review-20261120.json) confirms Windows time queries denied under non-admin collector despite signing/clock/token success. Next: address that account-specific observation boundary and validate scheduled health publication/revocation; do not infer it from elevated diagnostics. Root503 remains transport-only. G3 remains80%, readiness14/30 (46.7%). Gateway intentionally disabled.


**2026-11-20: post-recovery bounded observation prepared.** New pinned recovery revision first verifies disabled task, accepted stopped worker, unchanged installed sources and checkpoint, no incident markers or listener, and exclusive lease. Observe inventories health task metadata and unauthenticated local actuator health without reading credentials. Apply starts once with an independent three-minute stop and requires 90 continuous seconds of advancing same-worker status, fresh successful TLS observations and denial acceptance; cleanup stops/disables and removes guard. This is not the thirty-minute soak, scheduled health publication or broker API acceptance. Local sample tests cover duration and stale/changed/blocked/failed observations. Runtime pending; G3 unchanged.

**2026-11-20: automated denial recovery accepted.** [Queue evidence](evidence/queued-denial-recovery-20261120.json) records diagnostic, inspection, failures, correction and successful recovery ea723866-1fa0-45e9-a0e4-586d61d5c267. Updated runner and relay confirmed; no manual script/report transfer after bootstrap. Fixed JSON timestamp coercion and scheduler UTC/local trigger comparison; actual boundaries 06:20:52Z and 11:50:52+05:30 represent the same instant. Backup and pinned instrumentation verified; one start; new instance dc2c6bb7250543a4af8ad6ad59865762 reached TRANSPORT_READY with advancing sequence and denial checks passed. Stop/disable and guard removal verified; failure and cleanupFailure null. Source hash verified against returned execution. Original intermittent denial cause remains unproven. No broker credentials, orders or application unlock. Six isolated recovery and five resume workflows plus generated-receipt regression passed locally. Next: reviewed bounded transport observation and application-health recovery using the queue. Gateway intentionally remains disabled. G3 remains80%; readiness14/30 (46.7%); this short capture adds no unattended acceptance credit.


**2026-11-20: catalogue upgrade verified; receipt timestamp fix.** Diagnostic 39ad5ceb-6f3b-44ea-9ed0-1b6fcd61b7d2 confirms elevated runner and recovery catalogue with matching CRLF source hashes. Observe job 9b7b4582-a222-4fb5-b5c4-9d4dec7b07da passed all five preflight groups but rejected the accepted timestamp after JSON date coercion. No mutation or start occurred. Builder and embedded receipt now preserve DateKind String; regression test evaluates the actual generated receipt against original evidence. Recovery remains pending; G3 unchanged.

**2026-11-20: separate queued denial recovery implemented; activation pending.** The new `paytm-denial-recovery` catalogue entry supports read-only Observe and explicit Apply. Apply is bound to the accepted incident hashes, verifies backups, installs the pinned denial-observation helper, preserves the session checkpoint and credentials, and attempts one start. A separate SYSTEM scheduled stop backs up normal cleanup; the job finishes with the gateway stopped and disabled, including on a successful capture. No broker login, orders or application unlock. Existing `paytm-transport-test` remains read-only. Local recovery workflow and queue integration checks passed; actual scheduled guard execution on the spare laptop is not yet verified. One relay/runner catalogue bootstrap is required before remotely submitting Observe then Apply. Original denial failure cause remains unproven. G3 remains 80%; Paytm readiness remains 14/30 (46.7%).


**2026-11-20: elevated connection and recovery preflight verified automatically.** Diagnostic599e9311-e7a8-4914-819f-ed8e5545fa73 confirms elevated=true and readable state. [Queued recovery preflight](evidence/queued-recovery-preflight-20261120.json), source hash verified, passes all five check groups: installed-source integrity, pinned incident/control, task identity/idle, exclusive existing lease, and stable file hashes/no listener. Task Ready/enabled, previous exit1; same blocked instance/sequence3860 and application locked. Outer transport result remains FAILED correctly; preflight success is not recovery or broker readiness. No production writes, restart or marker removal performed. Local fixture rejects foreign task, held lease, code drift and changed incident. Next: separate write-capable guarded recovery handler bound to this receipt; existing Observe catalogue must remain read-only. G3 remains80%, total14/30 (46.7%).

**2026-11-20: automation reconnected after laptop startup; elevated inspection pending.** [Diagnostic](evidence/automation-restart-20261120.json) completed via the same job ID after a result-fetch timeout; runtime hashes verified, session5, elevated=false. Startup shortcut launches a normal interactive process; protected gateway files are unreadable (UnauthorizedAccessException), local18889 listener closed. Do not reuse yesterday's lock evidence as current proof. Windows time reports Hold/stale resync data; source query denied; recheck after elevation. Next human intervention is elevated runner restart with existing updater, preserving terminal pending delivery. No gateway reset, pairing change or new test requested. G3 remains80%, total14/30; current availability not accepted.

**2026-11-19: automatic denial investigation completed; recovery not activated.** [Runtime evidence](evidence/queued-denial-investigation-20261119.json): three synthetic loopback 403 checks passed on spare curl (CONNECT exit56, plain HTTP exit0). Installed transport matches both manifest and reviewed pre-change source. Last recorded normal TLS probe succeeded (CONNECT200, certificate0, HTTP503), but original denial response was never saved. Earlier TLS timeouts are not proof of the denial failure cause. Gateway remains BLOCKED instance1f2c636c108042898f3c58143e00d9c7/sequence3860 with application locked. Production evidence instrumentation locally passes 67 adapter assertions plus denial-specific tests, but is not installed. Guarded recovery requires backup/identity checks and installation before one observed start; current queue catalogue is read-only and does not perform that mutation. No manual test requested. G3 80%, total14/30 (46.7%).

**2026-11-19: denial investigation prepared.** Queued transport v3 collects installed transport/manifest hashes and bounded historical TLS metrics when blocked, and exercises three synthetic 403 responses on an ephemeral loopback-only server. It does not restart the gateway or establish VPS policy correctness. Production helper now records fixed case/exit/timeout/status fields before the existing denial failure; acceptance rules unchanged. This instrumentation is locally tested, not installed. Local tests: three actual Windows curl formatting cases, seven classification cases plus first-cause preservation, and 67 adapter assertions/six mocked workflows. Remote capture pending.

**2026-11-19: remote execution and version update accepted; transport remains blocked.** Runtime evidence: [queued-test-runtime-20261119.json](evidence/queued-test-runtime-20261119.json). Three real queued jobs executed and returned evidence, including a deliberate failure and a newly committed test version, with no manual spare commands. Current gateway failure is TRANSPORT_DENIAL_FAILED; application remains locked. The denial response itself was not captured, so do not infer policy bypass or reset the failure marker. Password-dependent and VPS jobs are still outside this catalogue. G3 80%, total 14/30; no new readiness checkpoint.

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

The update validates the old runner hash, refuses pending work by default (completed-result preservation option below), stops only the identified same-user installed runner, preserves a backup and pairing, installs the diagnostic helper and new runner, and starts it again. Any claim racing with the stop remains preserved and is marked interrupted rather than repeated. No VPS change. Tell the agent when the update completes; it can submit `Send-AutomationJob.ps1 -Kind diagnostic` from the development laptop and read the returned report directly.

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

## Preserve completed delivery during a runner update

2026-11-19 local regression reproduced ISO timestamp conversion when a saved result is reloaded with default `ConvertFrom-Json`. If the first delivery was accepted but its response lost, converting `+00:00` strings to local DateTime strings changes the terminal JSON and the relay correctly rejects the retry as immutable. This is a confirmed retry defect; the spare laptop's exact pending body/delivery failure still requires runtime confirmation.

Common API parsing and worker pending reads now use `-DateKind String`; PowerShell 7.5+ is required (both machines run 7.7). `Update-AutomationDiagnostics.ps1 -PreserveCompletedPendingResult` permits only SUCCEEDED, FAILED or INTERRUPTED pending states with a valid job ID. RUNNING stays blocked. The updater retains pending bytes, updates Common alongside runner/helper and starts the worker so it can redeliver, not re-execute, the completed job. Do not delete pending.json or change terminal server records.

Run the corrected updater locally in elevated PowerShell 7 after pulling. It does not change gateway state or Windows time. Local TLS integration tests simulate an accepted result with lost reply, verify exact UTC and offset string replay, running-state rejection, completed-pending upgrade and result drain. If the original pending result was already changed or the network remains unavailable, preserve evidence and review instead of forcing acceptance.

## Current automated-session finding, 2026-11-19

**Automated delivery restored, 2026-11-19:** User confirmed RUNNER_UPDATE_VERIFIED; queued diagnostic returned with updated runner, elevation and Windows sync error 0. Subsequent diagnostics also returned automatically. [Evidence](evidence/automation-delivery-restored-20261119.json) shows gateway task Ready/exit 1, unchanged BLOCKED worker 75ecfd57f6874744a83611a856a8b161, TRANSPORT_UNKNOWN at observation-loop line 190 and no local listener. Delivery recovery does not establish the exact original pending-result cause. Sanitized SSH observation was omitted by the diagnostic allowlist; collection correction and redaction regression prepared. No gateway reset or readiness credit; G3 80%, total 14/30 (46.7%).

After the bounded batch finishes, pull and run the elevated updater with `-PreserveCompletedPendingResult` once to deploy sanitized SSH detail collection. RUNNING work still blocks the update. Next diagnostic returns only fixed SSH tags, booleans, attempt timing and stderr hash/count; raw stderr is never returned. Preserve gateway failure markers until the SSH cause is established. Existing incident-specific recovery scripts must not be replayed against this new failure.

## Focused SSH reachability check

The next diagnostic includes two observations to the fixed VPS address, port 22. Each has a six-second total deadline (connection wait capped at three seconds) and a 1024-byte read limit. It accepts a complete SSH 2.0/1.99 identification line, allows bounded preceding lines, and handles split TCP reads. It sends no client protocol bytes, credentials, authentication or forwarding requests. Only classification, byte count and timing are returned; raw server text is discarded. These probes may appear as unauthenticated disconnects in VPS logs.

This is current operator-context evidence, not gateway-account authentication or verified server identity. It cannot reconstruct the discarded historical SSH stderr. Local tests cover identification, fragmented input, immediate close, silence/deadline, byte limit and invalid protocol. A passed probe does not unlock the gateway or establish broker readiness.

Deploy with the existing elevated runner updater after pulling; confirm RUNNER_UPDATE_VERIFIED. The controller then submits a normal diagnostic and retrieves the result automatically. No manual JSON transfer, credentials, or gateway restart is required.

### Reachability result and next identity check

**SSH reachability accepted, 2026-11-19:** [Automatic diagnostic](evidence/automation-ssh-reachability-20261119.json) has verified runner/helper hashes. Both operator-context TCP/SSH identification samples passed (198 ms, 515 ms); no authentication attempted or host identity established. Gateway remains BLOCKED with the same UNKNOWN incident and closed local listener. Next: existing isolated scheduled signing test under the gateway account, with local Windows password input and automatic report collection. This is a fresh prerequisite check, not proof of the original cause or permission to clear markers. G3 remains 80%, total 14/30 (46.7%).

Run `ops/automation/Invoke-LocalGatewaySigning.ps1` once in elevated PowerShell 7. Enter TEST-SCHEDULED-KEY and the existing Windows marketbrain-gateway account password when requested, not the VPS password or SSH key passphrase. The temporary scheduled probe checks signing in session 0, verifies its task definition and cleanup, and saves a bounded latest result for automatic retrieval. The wrapper compares production gateway hashes before/after. Preserve any failure report; do not rerun recovery scripts against older incident receipts.

## Reviewed November 19 SSH-exit recovery

**Fresh gateway signing accepted; reviewed recovery prepared, 2026-11-19:** [Automatic evidence](evidence/automation-signing-current-20261119.json) verifies two signatures, session 0/non-admin identity, task exit 0/removal and unchanged production state; all six signing source hashes match. Recovery is bound to signing run ba3fa8bf42434bd1bbb1115f63f4c457 and stopped instance 75ecfd57f6874744a83611a856a8b161, sequence 9319, UNKNOWN attempt 13/stderr hash. Verified archive precedes one start; checkpoints preserved, application stays locked, same-worker 30-minute observation and failure stop/disable retained. Local adapter/gate/receipt/controller fixtures pass; actual recovery pending. Original cause remains unknown. G3 80%, total 14/30 (46.7%).

Run `ops/automation/Invoke-LocalGatewayRecovery.ps1 -ReviewedSshExit` once in elevated PowerShell 7 after pulling. Keep Docker/application running, keep the laptop awake and connected, and leave the console open for about 30-35 minutes. The application health gate stays locked throughout; no broker credentials or order calls are used. This is a deliberate one-time recovery, not a classifier change or a proof that the original unknown SSH failure is fixed.

The controller uses the existing installation and process ownership checks, rejects drift, verifies archive hashes before removing only this reviewed incident's three markers, preserves session checkpoint and account, and starts the existing task once. On failure it captures evidence and requests stop/disable through the existing owned-worker cleanup. Do not rerun automatically. The wrapper stores a completed bounded report at the existing automatic-collection path. Tell the agent when complete; no file transfer is needed. A pass establishes only this observation interval, not all-day stability or G3 completion.

Local verification: 42 recovery/archive assertions; 8 incident-gate cases; 15 receipt/snapshot rejection rules; 48 controller assertions across 8 mocked workflows. The success fixture accelerates time locally; the spare-machine observation remains 1800 seconds.

## Recovery TLS timeout follow-up

**Recovery reached transport, stability failed, 2026-11-19:** [Recovery evidence](evidence/recovery-tls-timeout-20261119.json) verifies archive/one start and initial pinned SSH/TLS transport. Observation stopped after 402.427 seconds/29 samples; three TLS timeouts followed proxy CONNECT 200, with no completed TLS handshake before the four-second connection deadline. Controller then timed out waiting for readiness. This establishes the failure phase, not whether ISP, VPS, proxy or Paytm caused it. All eight source hashes match. Cleanup preserved account/application lock; [automatic follow-up](evidence/recovery-stop-confirmed-20261119.json) confirms STOPPED sequence 273, task Disabled, local listener closed. Next: existing VPS direct-versus-proxy comparison, no recovery rerun or threshold changes. G3 remains 80%, total 14/30 (46.7%).

Use existing `ops/linux/TestPaytmUpstreamPath.sh` in the verified admin PuTTY session and invoke `mb_upstream_main`. Thirty direct/proxy pairs use the same four-second connect and six-second total deadlines, ten-second spacing, no credentials or service changes. Keep the Windows gateway stopped. Results describe current VPS paths, not historical cause; root HTTP 503 is not API readiness. The controller cannot run this VPS-admin step through its current fixed diagnostic catalogue.

## Concurrent VPS and Windows TLS capture

**Concurrent TLS comparison prepared, 2026-11-19:** One shared comparison ID coordinates a 60-pair VPS direct/proxy capture with a five-minute Windows supervisor capture. Local resume is bound to recovery 63fbd61a1619419cae809063f6b9c29e and verified STOPPED instance/sequence 273. Archive checked before one enable/start; no code/key/timeout replacement. Windows observes healthy and retry states, keeps application locked, and stops/disables on completion or failure. Timestamped bounded TLS samples return automatically after runner update. VPS result remains one manual JSON. Actual overlap and transport acceptance pending; G3 remains 80%, total 14/30 (46.7%).

After pulling, run the existing runner updater once in elevated PowerShell 7, then `ops/automation/Invoke-LocalTlsComparison.ps1`. The wrapper copies the bounded VPS command and displays a unique ID. Paste that command in the verified admin PuTTY session. When VPS_CAPTURE_STARTED=<id> appears, paste exactly that line into the waiting PowerShell prompt within two minutes. The wrapper refuses a different/late marker before changing Windows gateway state. VPS collection continues bounded even if Windows preflight refuses. Do not answer START-TEST or STOP in either window.

Windows initializes the locked local application, checks the reviewed stopped state, archives state, enables/starts once and waits for initial transport readiness. It then captures five minutes of supervisor observations, including reconnect/backoff states, with UTC timestamps and TLS phase timings. Existing controller cleanup stops/disables the gateway on completion or failure; keep PowerShell open and the laptop awake for cleanup. No production TLS deadline changes, broker credentials, orders, service code replacements or application route arming. VPS keeps its existing proxy service state.

VPS runs 60 direct/proxy pairs, typically 10-12 minutes (up to roughly 26 minutes with repeated request deadlines). Windows generally finishes in 6-8 minutes including preparation and cleanup. Stop a comparison if an unexpected state appears rather than replaying old recovery commands. The existing latest-result path receives the Windows report for automatic collection. Share the one VPS JSON printed by PuTTY and say both windows have finished.

A shared ID proves workflow association, not clock synchronization or temporal overlap. Review actual UTC intervals, clock evidence and repeated TLS timestamps before attributing simultaneous failures. Sampling is discrete and requests are not exactly simultaneous; no-failure results cannot prove the earlier cause. The status TLS_DIAGNOSTICS_CAPTURED_GATEWAY_STOPPED_REVIEW_REQUIRED means evidence collection completed, not readiness passed.

Local validation for this change: 29 archive/start assertions, 9 receipt rejection cases, 10 capture assertions across eight fake-clock workflows, 58 controller assertions across nine mocked workflows, bounded/redacted automatic comparison evidence, eight batch-assessment cases, Bash syntax and eight probe-classification cases passed. The full Git Bash 30/60-pair offline harness exceeded its local timeout and was terminated; it is not counted as passed. Native VPS execution and actual clock-aligned overlap remain unverified.

## Thirty-minute stability after paired capture

**Thirty-minute stability resume prepared, 2026-11-19:** Accepted paired capture 7553672c6c1a428983e9f096a087aa3f permits one reviewed resume of STOPPED instance 52b35c1b29c7491eace8cee72eed57d3, sequence 270, disabled task/exit 0. Receipt hash and comparison ID checked; verified archive before enable/start; no installed code/key/timeout replacement. Application remains locked during 1800-second same-worker observation; failure cleanup stops/disables and preserves account/evidence. Local tests: 29 archive/identity/start assertions, 13 receipt rejection cases, 48 controller assertions across eight mocked workflows. Accelerated fixture success is not runtime acceptance. G3 remains 80%, total 14/30 (46.7%).

Pull and run `ops/automation/Invoke-LocalGatewayRecovery.ps1 -AfterPairedCapture` once in elevated PowerShell 7 on the spare laptop. No runner update or PuTTY action is needed. Keep Docker/application running and the laptop awake; leave the console open for about 30-35 minutes. The controller verifies a full 1800-second worker interval and final advancing sample. On success, transport stays running for subsequent diagnostics, while the application remains locked and health acceptance pending. On failure, owned-task cleanup stops/disables it; do not replay this resume against changed state.

Completed result is placed at the existing automatic-collection path. Tell the agent when finished; no manual upload is required. This run neither proves the original intermittent fault fixed nor enables Paytm login, credentials, orders or application route arming.

## Priority: actual test execution, not only diagnostic delivery

**Thirty-minute gate passed with recovered timeouts; automation priority, 2026-11-19:** [Recovery](evidence/paired-resume-stability-20261119.json) passed 1810.146 seconds/127 observations with the same supervisor, account preserved and application locked; all seven source hashes match. Two TLS timeouts and three SSH attempts were recorded, so this is recovered transport, not fault-free stability. [Automatic recheck](evidence/paired-resume-automatic-recheck-20261119.json) confirms Running/TRANSPORT_READY and both TLS probes successful. Root HTTP 503 still does not establish broker API readiness. User correctly identified that job queue supports only diagnostic/intervention-test, while actual Paytm tests and updates remain manual. Prioritize execution/update integration before another manual readiness cycle. G3 remains 80%, total 14/30 (46.7%).

Current implementation is a transport/diagnostic foundation. Relay JOBS, sender ValidateSet and worker switch admit only diagnostic and intervention-test. It does not distribute new test versions, run real Paytm scripts, invoke VPS collectors, or collect password-dependent test results without a locally started script. Report pickup alone does not meet the user's unattended execution goal.

Next implementation milestone must deliver one complete real Paytm test end to end: controller queues a named/versioned test, spare runner obtains the reviewed source version, verifies it, executes within a time limit, and returns compact progress plus full bounded evidence. No manual copy/paste, pull, launch or upload during this acceptance. Start with transport observation that leaves the working gateway intact, then add health-collector and guarded recovery jobs. Existing deployment/catalogue setup may require one attended bootstrap; do not promise that all later job types or VPS privileges are already available.

Execution/update requirements: allowlisted job identity plus typed parameters and exact source revision/hash; isolated source staging; compatibility validation before activation; retain prior working runner on failure; per-job identity and durable execution/result state; no duplicate execution after lost acknowledgments; bounded serialized runs; explicit FAILED/INTERRUPTED/WAITING_FOR_USER states. Scoped local interactive helper handles required passwords on the spare laptop, never in relay results/chat. VPS collection needs a separately installed fixed-command adapter. Do not substitute an arbitrary shell-upload endpoint for reviewed jobs.

Acceptance sequence: (1) remote job runs and result is retrieved without spare-laptop commands; (2) second reviewed test version is delivered automatically; (3) forced failure produces usable evidence without losing the worker; (4) network interruption preserves the same job and does not repeat an executed mutation; (5) a required local intervention pauses/notifies/resumes with no secret transmission. These tests, not another successful basic diagnostic, establish the automation milestone. Dates cannot be promised before runtime acceptance.

## Versioned transport test execution — implemented, deployment pending (2026-11-19)

The relay, sender and worker now support `paytm-transport-test`. Each request binds an immutable Git revision, SHA256 and Observe/FailureFixture mode. The worker retrieves only the fixed repository job path, checks size/hash/PowerShell syntax, stages it under the job ID, and executes a child with a 120-second deadline. A receipt prevents repeated execution; pending completion survives failed delivery. RUNNING progress is best-effort; failed progress delivery never restarts a test. Full structured evidence is returned for test failures as well as success. Raw process output is counted, not uploaded.

Observe takes six credential-free TLS HEAD samples through the existing local proxy, verifies loopback listener addresses, same advancing supervisor, and locked application state. It does not change the gateway, application, accounts or trades. HTTP 503 can pass TLS transport checks but is not broker/API readiness. Failures remain FAILED rather than being relabelled as collection success. This is a transport observation, not a new 30-minute stability gate.

Local acceptance: nine relay tests passed, executor fixtures passed, and real local HTTPS relay + PowerShell worker integration passed for deliberate failure evidence, lost completion ACK redelivery without re-execution, and execution of a second source version. The integration substitutes local fixture source bytes and uses an isolated Windows user-state directory; it is not spare-machine or real broker acceptance. Remote source download and actual transport observation remain to be accepted after bootstrap.

One attended bootstrap is necessary because the currently installed worker cannot update its own catalogue and the existing relay rejects this new job kind. On the spare laptop, pull main, run `Prepare-AutomationTestBootstrap.ps1`; run `sudo -v` in the verified VPS admin PuTTY session, then paste the copied command. Expect RELAY_TEST_EXECUTION_UPDATED. Then run elevated `Update-AutomationDiagnostics.ps1 -PreserveCompletedPendingResult` on the spare laptop and expect RUNNER_UPDATE_VERIFIED. Existing queue, pairing, gateway and accounts are preserved. Relay code rollback is automatic if restart fails; runner backup is retained for review if startup fails. Do not re-pair or rerun initial installers.

After bootstrap the controller submits `Send-AutomationJob.ps1 -Kind paytm-transport-test -Revision <reviewed full commit>`. The spare laptop needs no manual pull/launch/upload for subsequent versions of this job. Additional job kinds, VPS collectors and real password-dependent helpers still require implementation/review. General unattended test coverage is not complete. G3 stays 80%, Paytm readiness 14/30 (46.7%).
