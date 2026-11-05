# SSH agent failure after Windows sign-out

**Current E236, 2026-11-06:** Agent diagnostic accepted in **4.957s**; four source hashes match `f8a3061` CRLF. ssh-agent was Running/automatic with zero exit codes; all six event queries were empty, and the checkpoint was unchanged. The production worker is stopped; historical cause remains unknown. [Next: dedicated-account local signing](paytm-agent-signing.md), one temporary task and one JSON, preserving production state. Full shutdown remains paused. Groups **100/100/40/0/0/0, 12/30 (40%)**, unchanged.

**Historical E235, 2026-11-06:** The baseline was healthy, but AfterLogoff stopped after 49.36 seconds with `TRANSPORT_WORKER_BLOCKED`. The worker recorded `HOST_AGENT_UNAVAILABLE` while checking `ssh-add -l`. All eight source hashes match the CRLF checkout of `7c9e321`. The error combines a timeout and a nonzero process exit; the report does not distinguish them or prove that signing out stopped the agent service.

The baseline and failure refer to the same worker. The final worker status is BLOCKED; advancing sequence numbers during failure cleanup do not prove health. Earlier signing flags are retained historical observations, not a fresh signing result. The last status observation is about 319 seconds older than the failure marker. Sleep, scheduling, clock adjustment and service availability need evidence rather than assumptions.

The post-sign-out application checks were not reached. Their false flags mean unverified in this phase, not a changed paper balance. No new G3.4 acceptance is earned. G1/G2/G3/G4/G5/G6 remain **100/100/40/0/0/0%**, or **12/30 (40%)** of the bounded Paytm readiness plan. This is not a percentage of whole-project completion or current uptime.

## Completed diagnostic: retained instructions and purpose

E236 accepts this diagnostic; do not repeat it. Continue with the [signing check](paytm-agent-signing.md). The diagnostic was `GetPaytmAgentFailureEvidence.ps1`. It preserves the existing session checkpoint and gathers:

- The current `ssh-agent` service state, start mode, PID and numeric exit codes, before and after collection.
- Service Control Manager events between 18:33:55 and 18:48:04 UTC on 5 November, filtering to this service. The exact report-derived window includes two-minute margins.
- Bounded OpenSSH, Windows power and clock-event IDs/times in that same interval. It omits arbitrary event messages, command lines, usernames and key material.
- The current worker failure, control, task and process observations, plus whether the protected checkpoint bytes stayed unchanged.

The Windows event/service subprocess is limited to 90 seconds. Each event source has a fixed result limit; missing, disabled, inaccessible or limit-reached logs remain explicit gaps. Empty logs do not establish a historical cause. Current service health does not prove gateway-account key availability. The collector never runs `ssh-add` under the administrator account as a substitute for the gateway identity.

Success means **diagnostic evidence captured**, not gateway repaired. This allows the next correction to address the observed service/agent condition. Do not reset markers, repeat the old native recovery, reimport keys, restart the gateway, repeat sign-out or proceed to shutdown before review. The current checkpoint still expects AfterLogoff; a future worker replacement will require a reviewed new baseline.

## Spare laptop handoff

Open **PowerShell 7 as Administrator**, using the same Windows account. No PuTTY, Pageant, Docker rebuild or sign-out is needed. Keep the original failed JSON unchanged in the Review folder.

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
& '.\ops\windows\GetPaytmAgentFailureEvidence.ps1'
```

Expected: `AGENT_EVIDENCE_CAPTURED_GATEWAY_RECOVERY_PENDING`. Share the **one** printed `paytm-agent-failure-<runId>.json`. If it says REVIEW_REQUIRED, share that same file without rerunning. No password or private key is requested. If the original report was moved, pass its exact path with `-DiagnosticReportPath`; the collector verifies its reviewed SHA256.

## Verification and references

**120 fixture assertions across service/event and eight controller scenarios**, plus the real local PS7-to-PS5 query (8.755 seconds), passed. These verify diagnostic collection, not gateway recovery.

Local fixtures cover running/stopped/missing/inaccessible services, bounded and empty event queries, disabled/inaccessible logs, truncated results, event redaction, rejected input, child timeout/nonzero exit/malformed output, incomplete service evidence, concurrent checkpoint changes and preservation of one report on failure. A separate real PS7-to-inbox-PS5 check exercises module loading and local service/event queries. These checks do not establish the spare laptop's current state or simulate real sign-out.

Microsoft documents the [Windows SSH agent and key custody](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement) and [bounded event filtering](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent). The current worker deliberately blocks on an unavailable agent; this diagnostic does not weaken that rule.
