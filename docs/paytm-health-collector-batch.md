# Scheduled collector integration batch

2026-11-20: Next combined runtime batch adds invalid-token HTTP401, replay rejection, wrong-boot rejection, real 11-second challenge expiry, fresh recovery and final revocation to -ManagedGatewayWindow -LifecycleCases. New negatives assert only unhealthy state; no broker call or route arm. Eight lifecycle fixtures pass on PS5.1/PS7; 28 scheduled-worker checks and 24 collector checks pass. Runtime pending. This batch is not durable installation or restart/sign-out proof.

2026-11-20: Combined collector runtime accepted (dd31561bc9804ee8ad966b2ca3b77851): 18 source hashes matched, 3/3 rounds accepted without findings, 55.923s total/13.280s worker; non-admin session0, signing/token authentication, Windows/VPS/Java clocks and proxy TLS passed. Final health revoked, application locked, task removed, gateway stopped/disabled and guard removed; policy unchanged. Automatic Observe d653af64-66e7-4344-9974-46404ea5f45b retrieved the same run and exact full-report SHA256. Root HEAD503 is transport evidence only. Durable installation and lifecycle remain pending; G3 stays 80%, total 14/30 (46.7%). No rerun of this accepted batch needed.

2026-11-20: Combined collector window implemented with -ManagedGatewayWindow. It validates the stopped gateway and application before prompting, uses existing local Windows credential/signing and custody checks, registers the limited collector task, then starts the gateway under an independently verified three-minute stop guard. Two fresh advancing transport observations are required within 45 seconds. Three collector rounds and final health revocation follow; normal/error cleanup stops/disables the gateway and removes the guard only after confirmed stop. A partially verified guard is retained for review. No persistent collector or trading enablement. Protected collector-batch-result.json is retrieved by queued Observe. Runtime acceptance pending; G3 remains 80%, overall 14/30 (46.7%).

2026-11-20: Background health-account snapshot access is accepted. Automatic inventory confirms application HTTP 200/UP and gateway Disabled, with a newer completed TRANSPORT_READY snapshot. Read-only Observe now checks a stopped collector baseline without requiring the old recovery instance/sequence/time; immutable sources, task identity, lock, no listener, no incident and trading-disabled checks remain. Apply still requires its historical exact recovery checkpoint and must not be used to restart this newer run. Full collector needs a separately reviewed bounded gateway start plus local health-account credential; no persistent collector is installed yet.

## Diagnostic rerun after E293

Run 5320e935c0034206bc0aed37383d20d4 rejected all three rounds. Findings were WINDOWS_TIME_SERVICE, WINDOWS_SYNC_UNCONFIRMED, WINDOWS_SYNC_AGE_UNKNOWN and GATEWAY_TLS_UNCONFIRMED; round two also reported CLOCK_BOUNDS_OUTSIDE_SCREEN. These findings do not establish whether the cause is account permissions, stopped services, connectivity, latency or command behavior. The original report omitted native errors, so that diagnostic gap must be closed before system changes.

All rounds submitted unhealthy state. Final revocation passed and the application remained locked. The failed temporary task was disabled and retained, not removed. The next invocation creates its own unique task and leaves the old task/evidence untouched; do not re-enable or delete the old task.

Update main and use the same command below. This is an evidence-producing rerun and can still return REVIEW_REQUIRED. Share its one JSON even if it throws. Native w32tm status/source exit codes and excerpts, curl exit code/stdout/stderr/timeout and clock bounds/latency are now retained. Each native text field is capped at 512 characters; the collector worker report uses a bounded 49,152-byte read limit (other scheduled modes retain 8,192). JSON depth preserves nested diagnostics. No tokens, HTTP authorization headers or decrypted ciphertext enter evidence. No permission, firewall or timing-threshold changes are made.

24 collector checks cover diagnostic retention, access-denied and proxy-error findings, bounded excerpts and existing rejection logic. 26 scheduled-worker regression checks also pass, including final revocation after collector rejection or exception. This update fixes missing diagnostics, not an established infrastructure cause. G3 remains 80%.

E292 accepts the restricted Java clock deployment in 210.824 seconds (3m31s). Authentication/body restrictions and challenge preservation passed before and after restart. The existing health token and paper account were preserved; writer and route remained locked. Eight script hashes and the source revision match 2a60978.

## Purpose and scope

Run the collector under the existing non-admin health account in session 0. One temporary task combines three rounds of live Windows/VPS/Java/transport observations and diagnostic health publication, followed by an explicit unhealthy report. No persistent collector is installed, no route is armed, no paper-read token is provisioned, and no trading or broker credentials are used.

Each round gets a fresh, boot-bound ten-second challenge, then reads local W32Time status/source, a nonce-bound pinned SSH VPS clock reply, Java epoch milliseconds through the restricted health endpoint, and TLS through the fixed loopback gateway proxy. Successful W32Time status establishes local service responsiveness; the automatic-start setting is read from the registry without requiring additional SCM permissions. Existing synchronization-age, wall-clock movement and five-second offset screening rules are reused. Each timed clock observation must fit a two-second bound; total collection/publication preparation must remain under eight seconds. These are infrastructure screens, not trading quote thresholds or proof of absolute UTC accuracy.

Only accepted live observations may be submitted as healthy. Java independently checks its container transport before accepting health. Invalid observations submit unhealthy bounds of zero; saved reports are never replayed as live inputs. HTTP/curl/SSH calls have fixed destinations, bounded execution, no proxy bypass or direct fallback, and no credential content in reports. Root HTTP 503 can establish TLS reachability but does not establish Paytm login/API readiness.

The worker attempts final revocation even if a round throws. Success requires all three rounds accepted and final UNHEALTHY_AND_LOCKED confirmed. Loss of the Java connection may prevent confirmed revocation; this produces review-required evidence and leaves server TTL enforcement as the bound, rather than claiming cleanup passed. The exact temporary task is removed only on success; failed tasks are disabled/stopped and retained for review. Account, keys, token custody, time settings and gateway configuration are preserved.

## Spare laptop

Use PowerShell 7 as Administrator. Keep Docker Desktop, MarketBrain and the existing managed gateway running. Update clean main and run:

```powershell
& '.\ops\windows\TestPaytmHealthScheduledAccess.ps1' `
    -TokenReportPath 'C:\MarketBrainData\Review\paytm-health-token-88ebf8fdc3de4c158351e86df95e7217.json' `
    -CollectorDeploymentReport 'C:\MarketBrainData\Review\paytm-health-activation-a3419285c4d94d4dbbe1d30370cbe944.json'
```

Enter the existing Windows **marketbrain-health** password. No PuTTY, SSH passphrase, rebuild, key import or new account is needed. The controller waits up to 90 seconds for the worker; the task has a 120-second execution limit. Share the one `paytm-health-scheduled-<run>.json` printed at the end.

Expected: `HEALTH_COLLECTOR_THREE_ROUNDS_PASSED_REVOKED_LIFECYCLE_PENDING`. If findings or an exception occur, preserve the report/task state before retrying. Each round records status, findings, failed phase when applicable, submitted bounds and timing without secrets.

## Validation and progress

Local coverage: 16 collector orchestration/assessment checks, 26 scheduled-task/worker fixtures including collector rejection and exception cleanup, and 21 existing collector/controller regression fixtures. Native PS5.1 workers exercise generated code; OS/SSH/HTTP are substituted in local fixtures. Actual background permissions, latency and provider transport require this spare report.

| Group | Accepted checkpoints | Completion | Pending |
|---|---:|---:|---|
| G1 Maintenance | 5/5 | 100% | None in this baseline |
| G2 Gateway | 5/5 | 100% | None in this baseline |
| G3 Recovery and health | 4/5 | 80% | Collector integration, durable installation and unattended lifecycle acceptance |
| G4 Login | 0/5 | 0% | Provider authentication flow |
| G5 Quotes | 0/5 | 0% | Fresh read-only quotes and rejection/recovery cases |
| G6 Telegram review | 0/5 | 0% | Combined authorized ACCEPT/REJECT/expiry/replay tests |

Paytm readiness remains 14/30 (46.7%). This counts accepted baseline checkpoints, not effort or whole-project completion. After this batch: durable collector installation and combined startup/logoff, stale-clock, outage/recovery, revocation and no-direct-fallback acceptance. G3 reaches 100% only when the remaining checkpoint is evidenced.

Accepted queued collector stopped-baseline preflight: 808e1f33-df04-49ad-9f3f-6f8e6c57f42e. Application UP, gateway Disabled, pinned sources and task identity intact, no active listener or incident. This is not live transport proof. Inventory checked key-custody/manifest.json (absent); actual custody validation uses custody-state.json and remains part of the full collector preflight. Do not recreate key custody based on that inventory field. Next is a bounded gateway/collector integration window with the local password gate.

## Combined local credential handoff

Run elevated PowerShell 7 under the paired spare-laptop user. Keep Docker, MarketBrain and the automation runner running. The gateway must begin disabled; the new mode starts and stops it itself. Do not manually start it, rerun old recovery Apply, or reopen old failed tasks.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\TestPaytmHealthScheduledAccess.ps1 `
    -ManagedGatewayWindow `
    -TokenReportPath 'C:\MarketBrainData\Review\paytm-health-token-88ebf8fdc3de4c158351e86df95e7217.json' `
    -CollectorDeploymentReport 'C:\MarketBrainData\Review\paytm-health-activation-a3419285c4d94d4dbbe1d30370cbe944.json'
```

Enter the existing Windows marketbrain-health password locally; no SSH passphrase or new credential is needed. Keep the window open until cleanup completes. Expected HEALTH_COLLECTOR_THREE_ROUNDS_PASSED_REVOKED_LIFECYCLE_PENDING. The protected summary retains stage, findings, task status and gateway cleanup; full diagnostic JSON remains locally at its recorded path/hash. An interrupted controller may leave no final summary; absence is not success. The independent guard requests gateway shutdown and Java health TTL bounds unrenewed health; neither establishes successful revocation without returned evidence.

## Remaining path to G6 (2026-11-20)

1. G3: run the combined negative/recovery batch, then install the durable collector and verify actual startup/sign-out, loss/recovery and stale blocking. The current temporary batch does not install that service.
2. G4: current Paytm app/auth contract, owner login, callback/replay validation, token custody and expiry/relogin. Owner interaction is required; no credentials in chat.
3. G5: instrument/entitlement checks and actual fresh Paytm quotes during market hours, with stale/malformed/rate-limit/recovery behavior.
4. G6: one combined Telegram session for ACCEPT, REJECT, 100-second expiry, stale/out-of-zone rejection, replay and unauthorized-action rejection. Keep quantity1, maximum notional5000 INR, quote age15 seconds, max slippage0.5%, review only. Requires owner interaction and accepted fresh quotes.

Target G6 execution as one session after G4/G5 acceptance. No reliable overall completion date is established before first live Paytm authentication/quote validation. Do not count local regression tests as runtime checkpoint completion or promise an iteration count. Group progress remains 100/100/80/0/0/0, total14/30.

Use the documented combined command with the additional -LifecycleCases switch. Expected HEALTH_COLLECTOR_FAILURE_RECOVERY_PASSED_DURABLE_INSTALL_PENDING. One local Windows password prompt; summary collection automatic. The expiry case deliberately waits11 seconds. Do not manually start the gateway.
