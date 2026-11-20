# Windows time observation for the health collector

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
