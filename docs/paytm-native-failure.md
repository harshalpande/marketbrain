# Read-only native health-check failure evidence

**Current E236, 2026-11-06:** Agent diagnostic accepted in **4.957s**; four source hashes match `f8a3061` CRLF. ssh-agent was Running/automatic with zero exit codes; all six event queries were empty, and the checkpoint was unchanged. The production worker is stopped; historical cause remains unknown. [Next: dedicated-account local signing](paytm-agent-signing.md), one temporary task and one JSON, preserving production state. Full shutdown remains paused. Groups **100/100/40/0/0/0, 12/30 (40%)**, unchanged.

**Historical E235, 2026-11-06:** Session baseline passed; AfterLogoff stopped after **49.36s** with `HOST_AGENT_UNAVAILABLE` in the background worker. All eight source hashes match `7c9e321` with CRLF. The report does not distinguish an SSH-agent query timeout from a nonzero exit. [Next: read-only service/event evidence](paytm-agent-failure.md), one JSON; preserve the checkpoint and pause sign-out/shutdown testing. Current gateway health is blocked. Groups remain **100/100/40/0/0/0, 12/30 (40%)**, with no new checkpoint accepted.

**Historical E234, 2026-11-05:** Native recovery and 30-minute observation accepted: **1847.099s total, 1809.708s observation, 129 observations**, all six source hashes match `60cc983`. Eight-file archive verified, one start, same worker/SSH child, zero transport failures/reconnects; both application route checks, final application/writer locks and unchanged INR100000 account pass. Original historical native operation remains unknown. [Next: baseline, actual Windows sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases. A missing application-checkpoint callback was caught locally and corrected before handoff. No recovery/network repeat. Groups remain **100/100/40/0/0/0, 12/30 (40%)**; G3.4 closes only after its final runtime report passes.

**Historical E233, 2026-11-05:** Corrected native evidence completed in **6.801s**, four sources match `07242e7`. Both executable signatures and metadata are complete; three installed hashes match and selected policy queries are empty. The gateway is still stopped; original native operation remains unproven. [Next: archived native-process correction, one restart and 30-minute observation](paytm-native-recovery.md). Cleanup preserves the first failure and records native operations; a denied stop is ignored only after confirmed child exit. 398 local assertions pass; actual gateway-account recovery and soak remain pending. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**.

**Historical E232, 2026-11-05:** The supplied `04c5384f7d4f423a99287eb3e796942d` report took 13.116s. Its four source hashes match `d372adc`; three installed helper hashes match their manifest. All three selected security event queries succeeded with no matches, and administrator `curl --version` returned 0. Both executable metadata rows failed with `CommandNotFoundException`. Therefore the original capture-success label was too broad: executable hashes, signatures and ACLs were not collected. This was a diagnostic defect, not proof that either executable was absent or the gateway recovered.

The corrected reader loads Management, Utility and Security from its own `$PSHOME/Modules` manifests instead of relying on inherited module discovery. The missing command's name was not recorded in the old receipt; module discovery is a plausible explanation, not a proven spare-host root cause. Each metadata step now records its stage, and any incomplete metadata makes the collector return `REVIEW_REQUIRED` while retaining the report. Actual PS7-to-PS5 verification with module discovery disabled collects both files successfully. No ACL or security policy is relaxed.

**Historical E232 collection command, now completed; do not rerun it for E233.** It gathers the missing metadata; it does not restart the stopped worker or clear its failure markers. No PuTTY, Docker rebuild, password, sign-out or reboot is required. The original gateway error5 operation remains unconfirmed. No matching events only means none of the selected event IDs were found in that ten-minute window.

**Historical E231, 2026-11-05:** The 3.16-second inspection passed. Five source hashes match `2ce584c`. Worker `6e74e3275a014678bb886b4574cfe45f`, PID18156, is absent; its task is enabled but Ready with result1, and the heartbeat does not advance. The same worker previously passed E228 network recovery. It later recorded `HOST_RUNTIME_FAILED` and a first-cause `Win32Exception`, native error **5 (Access denied)**, during `OBSERVATION_LOOP`, line77. Last recorded worker elapsed time was **1387.3 seconds** (about 23 minutes). No session baseline exists.

The recorded line is consistent with the installed transport helper's `NativeCommand.Run(curl.exe, ...)` health-check call. This is a source-based inference: the saved exception lacks the script name and native operation/stack. `NativeCommand.Run` can raise errors during process start, wait or timeout cleanup. This report does not establish an executable permission problem, antivirus block or process-exit race. The old SSH observation is explicitly from attempt2; the later transport state reached attempt5. Do not attribute this new failure to that old network-denial observation.

## Next command

Use **PowerShell 7 as Administrator** on the spare laptop. No Docker, PuTTY, account password, sign-out, reboot or gateway restart is needed.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell 7 as Administrator.'
}
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\GetPaytmNativeFailureEvidence.ps1'
```

Expected: **NATIVE_FAILURE_EVIDENCE_CAPTURED**. Share the one printed `paytm-native-failure-<runId>.json`. If the reviewed input report was moved, supply its original bytes with `-DiagnosticReportPath`.

The batch reads current failure files and installed helper hashes, then queries a fixed ten-minute window around **2026-11-05 09:45:13.6603845 UTC**. It gathers up to32 selected events per channel from AppLocker, Code Integrity and Defender, with explicit missing/disabled/access-denied/truncated results. It reads hashes, signature status and access descriptors for Windows curl/PowerShell, then runs **curl --version locally under the controller identity**. No broker URL or credential is supplied. A controller-account success does not prove gateway-account execution. The script does not change ACLs, policies, task state, gateway files or failure markers.

The subprocess has a90-second deadline. Worker/hash evidence is checkpointed first so a failed or timed-out native query still leaves one report. Event payloads, messages, usernames and command lines are not copied: only IDs, timestamps, approved filename labels and numeric error/PID fields are retained. File access descriptors contain security identifiers but no passwords or keys.

A completed capture is not a recovery pass. Matching policy events may explain the denied operation; absent events do not rule out policy restrictions or a process-control race. Keep session/logoff/shutdown testing on hold and preserve existing markers until this report is reviewed.

## Verification and progress

117 local assertions cover six event-query scenarios, five collector outcomes, bounded/redacted capture, input/installed-file preservation and partial evidence on native failure/timeout. The actual Windows PS5 worker also completed on the development host; privileged collector boundaries were fixture-tested. Corrected spare metadata collection remains pending. A real PS7-to-PS5 test checks both actual hashes, signature results and access descriptors with module discovery disabled, plus missing-file handling. Partial metadata is explicitly tested as REVIEW_REQUIRED.

Groups remain **100/100/40/0/0/0**, **12/30 (40%)**, with no increase. E228 remains accepted at its captured scope; current worker health is blocked. This is not a repeat of the already accepted network fault test.

Event categories follow [Microsoft AppLocker event documentation](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/using-event-viewer-with-applocker), [App Control troubleshooting](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/appcontrol-debugging-and-troubleshooting), and [Defender ASR events](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-windows-events). Audit events and enforced blocks are kept distinct by event ID; no security policy is relaxed by this diagnostic.
