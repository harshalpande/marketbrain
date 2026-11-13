# SSH incident correlation: E243

The reviewed recovery receipt `ba7938fb742c4ac8bc289a2dcd2ff175` has SHA256 `BA07CFC8C9A870B74906BE5286F099370A3FCDD52EA237B8CB43446DECBA88A0`. Initial transport and application TLS succeeded; a curl timeout followed, then SSH reported TCP_CONNECT_TIMEOUT. Failure cleanup verified STOP, final application locks and unchanged account. No recovery or sign-out rerun is authorized by this collector.

The owner supplied a successful VPS gateway-key login at 13:32:22 UTC and a later successful administrator TCP-port check. Neither proves that the failed reconnect succeeded. Global SSH settings do not resolve account-specific Match rules. No evidence yet establishes MaxStartups throttling or scanner traffic as the cause. Do not change SSH limits or authentication as a presumed fix.

## Purpose and limits

Read the existing VPS ssh.service journal for 13:30–13:35 UTC on November 13. Group gateway-related events by server PID, retain gateway source address/port where logged, categorize disconnects/timeouts/forwarding denials and count possible throttling/penalty events. No raw messages or unrelated scanner addresses leave the collector. Query timeout20 seconds; maximum2001 rows; empty, malformed, failed and potentially truncated queries remain incomplete. Existing rotated/missing logs may not be recoverable.

The Windows wrapper combines this with the exact reviewed recovery receipt into one JSON. It does not contact a broker, start a task, read private keys or change installed gateway files. No production progress checkpoint is earned. Clock synchronization at the incident time is unknown; the old Windows report lacks its source port, so exact cross-host connection matching may remain impossible. If this evidence cannot resolve the cause, instrument connection identity in a separately reviewed recovery rather than repeat historical log collection.

## Spare-laptop steps

1. Open PowerShell7 on the spare laptop. Administrator elevation is not needed for this read-only wrapper. Pull the committed scripts:

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\GetPaytmSshIncident.ps1' -Phase Prepare
```

2. In your verified `marketbrain-admin` PuTTY window, type `sudo -v` and enter the administrator password if requested. Then paste the clipboard command and press Enter if needed. It runs automatically; do not type START-TEST or STOP. Python3 is used on the VPS; nothing is installed. If Python3 is missing, share the error rather than install anything.
3. Copy only the complete printed block from `BEGIN_PAYTM_SSH_INCIDENT` through `END_PAYTM_SSH_INCIDENT`, including both markers. Wrapping/whitespace inside its encoded data is tolerated. This encoding is for reliable transfer, not encryption.
4. Back in the same PowerShell window:

```powershell
& '.\ops\windows\GetPaytmSshIncident.ps1' -Phase Collect
```

Expected collection status: `SSH_INCIDENT_CAPTURED_REVIEW_REQUIRED`. This is successful evidence collection, not a health pass. Share the one printed `paytm-ssh-incident-*.json`. No rebuild, gateway restart, Pageant, sign-out or shutdown. Approximately2–3 minutes including copying; VPS query bounded at20 seconds.

## Local verification and progress

Nine Python tests verify connection grouping, event classification, redaction, timeout/nonzero/malformed/empty/truncated queries and limits on conclusions. Six PowerShell collection workflows cover ordinary and whitespace-wrapped blocks, missing block, wrong window, incomplete VPS collection and altered receipt; Prepare is also checked. VPS journal calls and clipboard are mocked locally; actual VPS evidence is pending.

G1 VPS100%; G2 unattended foundation100%; G3 recovery40%; G4 login0%; G5 quotes0%; G6 Telegram review0%. Accepted bounded readiness checkpoints remain12/30 (40%), not whole-project completion or current transport availability.
