# E256: runtime latch/recovery accepted

**Current E256, 2026-11-15:** Actual runtime listener latch/recovery accepted in33.485s. Nine source hashes match1c1b99c CRLF; exact worker conflict persisted10.868s, verified marker archive, one start, fresh recovered worker. Java absent-tunnel failure and subsequent lock passed; account/container/final locks preserved. G3.2 complete: groups100/100/80/0/0/0;14/30 (46.7%). [Next: fresh read-only three-clock snapshot](paytm-clock-refresh.md); G3.5 remains open.

The runtime test below is complete. Do not rerun it.

# Runtime listener latch and controlled recovery

E255, November15,2026. This batch intentionally interrupts the installed gateway briefly. Run with other MarketBrain jobs idle and Docker/the existing application container running. No broker credentials or trades are used. No VPS change, build, task re-registration, key import or application restart.

## Procedure

1. Verify accepted installed sources, owned task/listener, locked Java diagnostic authority, locked paper writer and current paper account. Require the initial Java HTTPS diagnostic to pass.
2. Disable transport through its existing control file. Wait for the existing supervisor to close its SSH child and report LOCKED. Query the previously armed Java diagnostic; it must return transport failure and lock, then remain locked on the next request. This is operational no-direct-fallback evidence for the diagnostic route, not a universal network egress proof or broker-client acceptance.
3. Bind an exclusive owned test socket to127.0.0.1:18889. Accept no connections and send no requests to it. The disabled supervisor still checks that the port is free, so its actual production code must exit1 and publish BLOCKED/TRANSPORT_LISTENER_CONFLICT for the exact observed worker and installation. Any different failure stops the procedure.
4. Dispose the owned socket, verify no listener remains and observe the task/markers for10 seconds without restarting it. The expected latch must remain, demonstrating no automatic recovery after conflict removal.
5. Disable the owned task, hold its instance lease, verify exact marker identities and installed hashes, copy status/blocked/startup-failure into an administrator-protected unique archive and verify all hashes. Recheck all three hashes before deleting only those test-owned markers. Existing session checkpoints and unrelated evidence are preserved.
6. Set LOCKED/DISABLED, re-enable the unchanged task and make exactly one start attempt. Require a new worker in LOCKED, then enable transport and verify readiness. Java must still be locked until explicitly rearmed for the final credential-free HTTPS diagnostic.
7. Lock Java again, verify writer lock and unchanged account/container/image/start time. On an error after mutation, request persistent STOP, disable/stop the owned task and preserve evidence. First failure, cleanup failure and stop failure are recorded separately; no blind retry or unrelated marker removal.

The private archive is intentionally retained on the spare laptop. Only one shareable JSON is needed.

## Run

Use elevated PowerShell7 in the spare repository after pulling main:

```powershell
& '.\ops\windows\TestPaytmRuntimeLatchBundle.ps1'
```

No PuTTY/Pageant. Allow about2-3 minutes. Readiness waits are bounded to30/60 seconds; latch wait30 seconds; the quiet interval10 seconds. Expected `RUNTIME_LISTENER_LATCH_AND_RECOVERY_PASSED_CLOCK_PENDING`. Share the printed `paytm-runtime-latch-*.json`, including on failure. Do not clear markers, reinstall or rerun a recovery script on failure.

## Acceptance and limits

Spare acceptance remains pending. Together with accepted E252 TLS/proxy, E253 SSH and E255 listener evidence, a successful reviewed run is intended to finish G3.2: G3 would become80%, overall14/30 (46.7%). G3.5 still needs clock/health enforcement acceptance. This test does not change the OS clock, claim true-time accuracy, exercise every security reason in the running daemon, or enable login/quotes/orders. Current progress remains13/30 (43.3%).

Local verification:23 helper assertions cover exact failure identity/scope, real archive files and hash checks, one restart, marker preservation, socket disposal on failure and no recovery on unrelated failure. Six controller workflows cover success, preflight failure, runtime failure, application-lock failure, account drift and a secondary stop failure. Privileged APIs are mocked locally; the10-second quiet interval is exercised. Runtime acceptance requires the spare report.
