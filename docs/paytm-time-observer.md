# Windows time observation for the health collector

2026-11-20: Queue job 96cbd8af-7d6e-40d4-8e2f-fb67f14bf299 recovered the local probe: Windows batch logon accepted (code 0), limited task definition valid, then TIME_ACCOUNT_NO_REPORT. Temporary task removed. This is not a password failure. Preserve scheduler exit/status before the missing-report check and collect bounded exact-task operational events via Observe. No authentication replay; G3 remains 80%, readiness 14/30 (46.7%).

The failed scheduled collector reports show that signing, VPS clock access and token authentication succeeded, while local `w32tm` queries returned access denied. Microsoft documents local administrator membership as a requirement for this tool: [Windows Time Service tools and settings](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings).

The implementation separates privileged observation from health publication. It does not add `marketbrain-health` to Administrators or change W32Time configuration or permissions.

- A fixed SYSTEM task, `MarketBrain-Time-Observer-v1`, runs only `/query /status /verbose` and `/query /source`, reads service state, and atomically publishes a bounded snapshot every second. It starts at Windows startup. It has no network listener, caller-supplied commands, application token, or broker credentials.
- Its script and snapshot live under `C:\ProgramData\MarketBrainPaytmHealth\time-observer-v1`. SYSTEM and Administrators have full access; the existing health SID has read/execute access. Existing installation paths/tasks cause Apply to stop rather than overwrite them.
- The collector checks trusted ownership, absence of untrusted write permissions, no reparse points, a 16 KiB limit, matching Windows boot and performance-counter frequency, and at most eight seconds of monotonic age. Snapshot age is added to reported sync age. Failed reads or invalid evidence fail closed.
- Existing VPS/Java clock bounds, TLS validation, collection deadline, one-use health challenge and final revocation remain required. A fresh Windows snapshot alone never grants trading authority.

The new `paytm-time-observer` queue kind supports Observe, Apply and an isolated FailureFixture. Sources are pinned to a committed revision and SHA256. Apply creates only this observer and checks two advancing snapshots as the administrator controller. **That result is not proof of access by the health account.** The next scheduled collector test must prove actual non-admin access, health publication and revocation. No existing failed health probe is automatically restarted or modified.

Local verification covers ten timestamp/schema cases, read-versus-write ACL boundaries, three installation workflows, the existing collector fixtures, relay validation and real local TLS queue delivery. SYSTEM runtime installation is accepted; restart lifecycle and health-account acceptance remain pending. G3 stays 80%, Paytm readiness 14/30 (46.7%).

## One-time catalogue activation

On the spare laptop, use elevated PowerShell 7, pull the reviewed commit and run `ops/automation/Prepare-AutomationTestBootstrap.ps1`. Paste its generated command into the verified VPS administrator PuTTY session after `sudo -v`; expect `RELAY_TEST_EXECUTION_UPDATED`. Then run `ops/automation/Update-AutomationDiagnostics.ps1 -PreserveCompletedPendingResult`; expect `RUNNER_UPDATE_VERIFIED`. Pairing and existing job history are preserved. No observer installation occurs during this bootstrap.

After capability verification, the controller can send Observe and Apply through the queue and retrieve their evidence automatically. A partial installation must be inspected before recovery; do not delete the directory or reapply blindly. The helper intentionally stays running after a successful Apply, unlike the bounded gateway capture jobs.

## Runtime acceptance, 2026-11-20

[Queued evidence](evidence/time-observer-runtime-20261120.json) records the initial JSON identity conversion failure, disabled-task inspection, correction and successful recovery. The recovery accepts only a disabled task with the pinned worker hash, exact action and SYSTEM/startup identity; it does not overwrite the worker. Boot identifiers remain JSON strings across PS5/PS7. Two fresh advancing snapshots passed; the observer stays running. The actual non-admin collector still needs separate acceptance.

## Health-account probe and remaining groups

The attempted cross-account S4U registration failed before task creation. Microsoft requires the target password even for this S4U registration case: [official security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks). The queued Apply now stops on an already-running observer with LOCAL_PASSWORD_REQUIRED instead of repeating registration. No permission policy is weakened.

Run `ops/windows/TestPaytmTimeAccountAccess.ps1` in elevated PowerShell7 on the spare laptop after a fast-forward pull. Enter the existing Windows marketbrain-health password locally. It registers one limited Password-logon task, verifies session0/exact SID/non-admin status, three advancing snapshots and actual write-access denial on worker/snapshot files. It never writes through the denial-test handles. The task has a one-minute limit; the controller waits at most40 seconds and removes only its own task. Windows temporarily retains the task's logon credential until task removal; no password is written to project files or transported by the queue. Cleanup failure is retained as failed evidence.

The protected `time-observer-v1/account-probe-result.json` is automatically available to the next queued Observe. No report upload is needed. Successful local reads do not prove DPAPI, network authentication, health publication or lifecycle. Those require the subsequent full collector batch.

| Group | Baseline accepted | Next work |
|---|---:|---|
| G1 VPS maintenance | 5/5 | Preserve accepted baseline; targeted health checks when infrastructure changes |
| G2 Gateway | 5/5 | Preserve identity/custody/startup guarantees during collector integration |
| G3 Recovery/health | 4/5 | Non-admin access, full collector publication/revocation, durable lifecycle and no fallback |
| G4 Login | 0/5 | Verify current provider contract/app; owner login, callback rejection, token custody/expiry |
| G5 Quotes | 0/5 | Entitlements/mapping, actual timestamped quotes, stale/error/rate-limit handling |
| G6 Telegram | 0/5 | Real ACCEPT/REJECT/expiry/replay/unauthorized batch with fresh quotes |

Local G4/G6 regression suites (25 JUnit tests) passed on2026-11-20, including login preparation's38 internal checks. They are engineering evidence, not runtime checkpoint credit. G4 login needs owner interaction; G5 market freshness needs market-hours data; G6 requires the configured Telegram user. Report these dependencies separately from automated work rather than rerunning unrelated accepted G1/G2 milestones.

### Registered-task validation correction

The local credential run created its task but stopped before execution on TASK_DRIFT; cleanup succeeded. The prior report cannot identify which field differed. The validator now compares the resolved Windows SID, accepts null as an absent trigger collection, and retains mismatch reasons/counts without recording command contents. Foreign identities, wrong logon type/run level, additional actions/triggers and altered commands still fail. Fifteen new cases run on PS5.1 and PS7. Rerun the same `TestPaytmTimeAccountAccess.ps1` after updating; the password remains local and the result is collected by queued Observe. No G3 checkpoint is closed by this code-only correction.

### Credential error reporting

The next local run retains only bounded numeric exception HRESULTs, selected numeric CIM fields and HRESULT tokens; it does not serialize error records, command lines or password parameters. WIN32-facility codes are distinguished from CIM status codes. Code1326 means username or password rejected, not proof of which input was wrong. Generic CLR/CIM errors cannot confirm password correctness. Known account-disabled/locked/expired, logon-right and access-denied codes are reported separately. No automatic credential retries or resets occur. Nine diagnostic fixtures and registration-failure workflow coverage passed in PS5.1/PS7.

Queued Observe reads the changing snapshot and protected report through the same 16KiB bounded, delete-sharing JSON reader. File lookup/I/O retries are limited to three; ACL policy, malformed JSON and size violations remain failures. The initial report-fetch IOException is not a credential error. Real file replacement and invalid-file tests passed locally.

### Read-only account investigation

Observe now compares the script's configured machine/account name with the actual account SID. It optionally queries at most50 failed-logon events in a three-minute window ending ten seconds after the saved local report. Only marketbrain-health event fields are retained; missing/unavailable auditing is not interpreted as successful authentication. No credentials are tested and no security policy is changed. The first attempt stopped on ADMIN_REQUIRED, so runtime identity/event evidence remains pending until the same paired runner is restarted from elevated PowerShell7. This elevation issue is separate from the earlier1326 error.

### Elevation verification for account inspection

`RUNNER_UPDATE_VERIFIED` alone confirms files, PID and startup nonce; it historically did not establish administrator rights. Use elevated PowerShell7 under the already-paired Windows user and run `Update-AutomationDiagnostics.ps1 -PreserveCompletedPendingResult -RequireElevation`. Expect both `RUNNER_ELEVATION_VERIFIED` and `RUNNER_UPDATE_VERIFIED`. Non-elevated invocation fails before stopping or replacing the current runner. The child also checks its own token before queue access, and records elevation in the matched startup receipt. No implicit UAC elevation or pairing reset occurs.

### Separate Windows authentication from scheduler registration

The elevated read-only check verified configured account SID and enabled state. Event lookup supplied no usable failed-logon evidence; password correctness remains unresolved. The local test now calls [LogonUserW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-logonuserw) once with BATCH logon and the fixed local health account before task creation. A returned token must match the expected SID; its handle is closed and temporary unmanaged password memory zeroed. No code runs under the token. Failure saves the Windows code and stops without registering a task or retrying. On success, normal task registration proceeds; a later scheduler failure is reported separately with credentialCheck.accepted=true. The local registration step still temporarily uses the password as required by Task Scheduler. No password is sent to the queue or written to evidence. This check may itself fail on batch-logon policy, so nonzero results must be interpreted by code rather than labelled wrong password generically.

Run the same TestPaytmTimeAccountAccess.ps1 after updating main; enter the existing health-account password locally once. Report retrieval remains automatic. Interop compilation and mocked workflows are verified; the new actual authentication result is pending.

Follow-up Observe f31d16fe-2a3e-4c3f-a01e-c44b9bb4f928 succeeded, but operational task events were unavailable or absent. It cannot establish the execution root cause. A local repeat now records scheduler status before cleanup, including on TIME_ACCOUNT_NO_REPORT. No account password reset is indicated.
