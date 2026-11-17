# Scheduled health signing and clock access

E287 accepts clock-key custody under Windows health SID ending1011. This next batch verifies that the same agent-backed identity works in a noninteractive Task Scheduler session and can read the already restricted VPS clock without a passphrase prompt. No key import, production collector, health token, broker login or trading permission is enabled.

## Combined procedure

- Verify the accepted receipt hash, exact account/SID/run, enabled state, membership/ACL, installed custody source hashes, public key and absence of staged private file. Verify the pinned public VPS key without ssh-keyscan.
- Read local LSA batch-logon allow/deny policy. Stop on health/group/unresolved deny rules; never remove a deny rule. Guest-only and verified unrelated local-user denials are distinguished using the same approach established for the gateway. Validate the health Windows password and fresh-process signing before granting rights.
- Add ONLY the approved health SID to SeBatchLogonRight if absent, and verify the exact allow-list delta and unchanged deny list. This narrow allow right is retained for the future collector; it is not administrator access. The C# API refuses the gateway or any other SID. Before/after lists and grant intent are recorded, including partial failures.
- Stage a protected worker and known_hosts file. Register one disabled, triggerless Password/Limited task with unique run identity, no restart, IgnoreNew, a120-second execution limit and battery operation allowed. Verify its complete action/principal/settings before enabling and demand-starting once.
- Worker verifies SID, non-admin token, session0, absent private copy, exact agent identity, two signing operations and one nonce-bound NTP-synchronized VPS clock reply through strict pinned SSH. The client uses BatchMode and zero password prompts. Each native call is bounded; controller waits at most90seconds for worker evidence. No timing-accuracy claim is inferred beyond the returned NTP status.
- Disable and stop only the exact owned task. On success unregister it and verify absence. On failure retain the disabled owned task and evidence for review; never remove an unrelated/drifted task. Protected diagnostic files are retained. The key stays in its existing agent.

## Spare laptop

Use PowerShell7 as Administrator, update clean main and run:

```powershell
& '.\ops\windows\TestPaytmHealthScheduledAccess.ps1'
```

Enter the existing Windows marketbrain-health password in the main window. No SSH-key passphrase, PuTTY, Pageant or second interactive window is needed. Expected HEALTH_SCHEDULED_SIGNING_AND_CLOCK_PASSED_COLLECTOR_PENDING. Share the one paytm-health-scheduled JSON. On failure do not retry, delete tasks or reset keys before evidence review.

## Local validation and remaining work

17 checks cover valid task shape and rejection of elevated/triggered/changed/enabled/unbounded tasks; exact policy delta and deny/drift rejection; native compilation of the same LSA interop source and rejection of a wrong SID before any policy call; native Windows PowerShell5.1 fixture workers for successful clock access, wrong nonce, signing failure, interactive session and wrong identity; controller syntax. Fixtures create no real tasks, policies, keys or external network connections. The disposable development PS7 runtime lacks compiler reference assemblies, so interop compilation was verified with the native PS5.1 compiler; the runtime spare uses installed PowerShell7.

Scheduled-runtime acceptance still requires the spare report. After acceptance: restricted health-token/collector provisioning and combined startup/logoff/loss/recovery acceptance. G3 remains80%, overall14/30 (46.7%). Explicitly announce G3=100% only when its remaining checkpoint is accepted.
