# Recovery after successful account signing

## Current E242: agent-query and native-phase diagnostics

The AfterLogoff report `3bec334f1adf423c986286eedd6697f2` failed with TRANSPORT_WORKER_BLOCKED / HOST_AGENT_UNAVAILABLE. Its Before baseline already recorded six TLS failures and seven connection attempts, so sign-out is not established as the sole cause. The latest curl probe timed out after 48782 ms; earlier failure was curl exit28 after proxy CONNECT200. The agent identity query's timeout/nonzero result was not retained. Application/account checks were not reached in AfterLogoff; false verification flags are not evidence of account changes. G3.4 remains blocked, progress 12/30 (40%).

Next: `RepairPaytmNativeProcess.ps1 -AgentProbeRecovery` in elevated PowerShell 7, Docker and the existing application running. It pins the reviewed failure receipt, requires the old worker to have exited and the task Ready/result1, verifies the original failure identity and pending AfterLogoff checkpoint, and checks source hashes/listener/locks. It refuses a still-running or changed worker. All old code, manifest, controls, failure files and checkpoint are archived with verified hashes. Only then are the native helper and host/runner/transport diagnostic helpers replaced. The native DLL is compiled and tested with local curl --version before replacement. No key import, account recreation or task re-registration. Failure after mutation uses the established STOP/disable handler; no automatic retry or rollback.

The native result now distinguishes process launch, wait, timeout cleanup and output collection timings. The wait budget is not an end-to-end operating-system scheduling guarantee. Agent query failures retain requested timeout, actual duration, exit code, timeout flag, known error category and Win32 code where available. Raw output, private keys, identities and passwords are not copied. The existing authentication checks and health/retry policies remain unchanged. This improves diagnosis; it does not claim to resolve the original availability failure.

Run once, allow about 35 minutes, keep awake/connected. No PuTTY or Pageant interaction, sign-out or shutdown. Share the one printed `paytm-native-recovery-*.json` on success or failure. The existing success status is `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`, with recoveryMode AGENT_PROBE_AND_NATIVE_PHASE_TIMING. A successful recovery requires a new session baseline; the old pending checkpoint is archived and cannot be reused with a new worker. Do not run the historical recovery commands below.

## Historical E241: runtime recovery accepted

2026-11-13: receipt `2523f35ea19e4ff19defa635f3ff6967` completed successfully in 1839.806 seconds. All eight source hashes match the reviewed checkout with CRLF. Soak 1805.703 seconds, 129 observations, 44 health samples; same worker, one connection attempt, zero transport failures. Initial/final application routes passed, account preserved and final application/writer locks verified. No broker credentials or orders. Failure-stop verification is false because the success path did not require failure cleanup. The prior interruption's cause remains unknown; diagnostic instrumentation is not proof of a connectivity fix.

Next is the existing [sign-out/full-shutdown workflow](paytm-gateway-session.md), starting with a fresh Before baseline. Do not rerun recovery. No application rebuild is required. G3.4 is still pending until the real session and boot boundaries pass, so progress remains 12/30 (40%).

## Historical E240: diagnostic recovery on Windows

VPS report `paytm-upstream-caT91oDZ.json` completed 30 paired samples in 298 seconds: all 60 requests returned verified TLS responses, curl exit 0 and HTTP 503. Proxy CONNECT was 200 for every proxy sample. Proxy mean/max 122.46/234.57 ms; direct mean/max 76.85/187.06 ms. Service active before/after. This validates the sampled VPS paths only, not historical stability or broker API readiness.

Next use `RepairPaytmNativeProcess.ps1 -TlsDiagnosticRecovery` in elevated PowerShell 7 with Docker and the existing application running. It pins E239's connectivity receipt, verifies the exact disabled/stopped installation, old process absence, saved status, no new markers/checkpoint and free listener. An exclusive worker lease plus the controller installation lease protects the replacement. It archives and verifies transport source, manifest, controls and old status; atomically replaces only transport.ps1 with the pinned diagnostic source; updates the manifest, archives the old active status, enables the existing task and starts it once. No key import, task re-registration, broker credentials or trading actions. The existing 30-minute health observation, initial/final application route, account preservation and final locks still apply. Failure after mutation requests STOP and disables the task. Partial failures must be reviewed; do not rerun the earlier modes.

The patched worker retains numeric curl exit/timeout, proxy CONNECT, certificate result, HTTP status, elapsed milliseconds, timestamp and native exception type for its latest probe and first/last failed probes. No raw stderr, headers or response bodies are stored. Health classification, retry policy and timeouts are unchanged. Evidence survives reconnects and is included in failure projection. This is an instrumentation correction, not a claimed connectivity fix.

Allow approximately 35 minutes. No PuTTY interaction, Pageant, service rebuild or sign-out is needed. Share the single `paytm-native-recovery-*.json` printed at completion; the legacy success status remains `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`. `recoveryMode=TLS_DIAGNOSTICS_AFTER_PROXY_UNAVAILABLE` identifies this run. A successful runtime result is required before resuming fresh sign-out testing. Local tests cover the real atomic replacement and archive using mocked task APIs, the actual idle gate including timestamp normalization, first/last TLS evidence and redaction, unchanged transport behavior, and controller cleanup workflows. Current checkpoint credit remains 12/30 (40%).

## Historical E239: VPS upstream comparison

2026-11-13: connectivity receipt `ee5b3e88b928468c9443c8c6e51765ec` captured in 18.732 seconds; all three source hashes match. The four selected Windows event queries were enabled, successful, empty and not truncated. TCP samples reached VPS port 22 in 204/109/97 ms under the controller identity. Four installed file hashes match the manifest. The stopped worker's final saved state is BACKOFF/PROXY_UNAVAILABLE, three failures; control STOP, task disabled and process absent. These are diagnostic observations, not a new accepted recovery checkpoint. No historical cause is established.

Next: `ops/linux/TestPaytmUpstreamPath.sh`, invoked with `mb_upstream_main` in the already verified VPS admin PuTTY session. It compares 30 sequential pairs of credential-free HEAD requests to the fixed Paytm developer HTTPS root: through the existing loopback proxy and directly from the VPS. Each curl has a six-second deadline, an outer eight-second deadline, no redirects, and normal certificate verification; pairs are separated by ten seconds. Allow 5-9 minutes. It records curl exit, proxy CONNECT code, TLS verification code, HTTP status and elapsed request time. HTTP 503 can be a valid TLS response but never establishes broker API readiness. Raw bodies, headers and stderr are not collected. Service state is read before/after; an inactive proxy stops the collection without starting it. One private `/tmp/paytm-upstream-XXXXXXXX.json` file is retained. Windows gateway stays stopped.

No START-TEST prompt, sudo, key loading or credentials are needed. Run the copied Bash command once and share the generated JSON. `UPSTREAM_EVIDENCE_CAPTURED_REVIEW_REQUIRED` means capture complete, not connection acceptance. A failure on both paths suggests the VPS-to-upstream segment; proxy-only failure suggests the proxy path; neither is a definitive historical cause. If both paths succeed, Windows tunnel behavior and transient health failures remain unresolved. Progress stays 12/30 (40%).

## Historical E238: recovery stopped during observation

2026-11-13: report `47dc9332f38f4ee293ba6b414b12cc5d` reached a fresh authenticated worker and application TLS response, but timed out waiting for healthy transport during the soak. The last successful sample was at 234.165 seconds; later diagnostics show CONNECTING, three attempts and two failures. Verified archive and checkpoint removal succeeded. Failure cleanup stopped the worker; account and application locks were preserved. Do not rerun the older recovery command below against the changed state.

The user supplied VPS observations: proxy active, zero automatic restarts, loopback port 18888 present, no service journal entries in 06:20-06:29 UTC. These observations do not establish continuous connectivity. The original cause remains unknown. A failed TLS health probe currently loses its curl exit/timing detail before reconnecting; a missing SSH error is not proof that the network was healthy.

Next run `ops/windows/GetPaytmRecoveryConnectivity.ps1` in elevated PowerShell 7. It verifies the incident receipt, reads current worker/task/control evidence and installed hashes, queries four bounded Windows event categories during that UTC window in a 45-second subprocess, and makes three five-second TCP connection attempts to the VPS port 22. No SSH authentication, task start, application call, key access or configuration changes occur. Only the shareable report is written. Network samples run as the controller, not the gateway account, and cannot prove historical or end-to-end health. Disabled/missing logs and truncated results remain explicit. Empty events do not rule out an outage. Allow about one minute; share the single `paytm-recovery-connectivity-*.json` even if incomplete. Capture status is not recovery acceptance. Local event tests cover redaction, empty queries, denial, disabled/missing logs and truncation.

Progress unchanged: G1/G2/G3/G4/G5/G6 = 100/100/40/0/0/0; 12/30 (40%). No new runtime checkpoint accepted.

## Previous recovery handoff (historical; do not rerun)

Current E237, 2026-11-13: signing report 1d103203c982427caea56d4b0671b0e7 passed. All eight source hashes match 5e5dc61 CRLF. The session-0 account listed its expected key and signed twice without errors/timeouts. Worker elapsed2.662s; whole controller118.905s including interactive input. Temporary task removed; all seven production state hashes preserved. Original agent failure cause remains unknown.

The next script uses the established recovery controller with `-AgentSigningRecovery`. This mode replaces no installed code or keys. It verifies the exact accepted signing report, stopped production task, old process absence, seven state hashes, free transport listener, installation and locked application. It copies and verifies all seven files into a protected `agent-recovery-<runId>` directory. Only after verified copies exist does it remove the three old worker status/failure files and the old session checkpoint. Original report files remain intact. A partial failure stops for review; no automatic retry or rollback is attempted.

It starts the existing gateway once, requires a fresh worker, observes health for30 minutes, checks the application TLS route at the beginning/end, and verifies unchanged paper account plus final application/writer locks. Failure after mutation requests STOP and disables the owned gateway task through the existing failure handler. The old checkpoint is recoverable in the printed archive; it cannot be reused with a replacement worker.

Use PowerShell7 as Administrator, with Docker Desktop and the existing MarketBrain container running. No PuTTY/Pageant, key import, password entry or rebuild is needed. Keep the accepted signing and managed-transport reports in `C:\MarketBrainData\Review`.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -AgentSigningRecovery
```

Allow approximately35 minutes. Keep the laptop awake and connected. Share the one printed `paytm-native-recovery-<runId>.json`; the legacy filename/status comes from the reused controller, and `recoveryMode` identifies this no-code-replacement recovery. Expected status: `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`. On REVIEW_REQUIRED, share the report and do not rerun, delete markers or sign out.

After acceptance, establish a fresh Before session baseline, then repeat the sign-out and full shutdown phases. This recovery does not itself close G3.4. Progress remains G1/G2/G3/G4/G5/G6 =100/100/40/0/0/0;12/30 accepted checkpoints (40%). Root HTTP503 remains transport evidence only. Login, quotes and trades are not enabled.

Local validation includes29 recovery assertions using temporary files and mocked task operations, plus the existing controller failure/lock regression. Real spare-laptop recovery and observation remain pending.
