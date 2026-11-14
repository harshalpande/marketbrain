# Unattended health collector preparation

E276 accepts the actual runtime health lifecycle in 133.478 seconds. The remaining G3.5 work is unattended collection, not repeating the accepted stale-health test.

## Implementation sequence

1. Read-only inventory of proposed Windows/VPS collector identity and Windows task name, VPS Python/timedatectl availability, current image/account/writer/route state. This step creates no account/key/task and reads no private key content. Three mocked external-operation workflows pass locally: clean baseline, naming collision and remote failure. A collision is a finding, never permission to overwrite.
2. Install a dedicated VPS clock-reader identity with a forced fixed command, pinned host key, no shell, sudo or forwarding; use a separate key from administrator and gateway keys. The background collector must not use administrator credentials.
3. Provision Windows exact-account key/token custody and a bounded publisher worker. Provisioning may inspect Docker with administrator authority, but the ongoing worker should not need Docker administrator access. Bind the credential to the existing diagnostic endpoint; never provision broker/order authority. Preserve an explicit disable/revoke path.
4. Verify unattended startup/logoff, collector loss and recovery, token errors, stale blocking, bounded retries and final cleanup as a combined acceptance batch. Close G3.5 only after accepted evidence, and explicitly announce G3 100%.

The current script only performs step 1. It does not prove future account privileges, key custody, task logon or unattended operation. The existing managed gateway remains unchanged. Its preflight also checks time-service settings and account/container preservation. The report records booleans and safe metadata, not credentials.

## Spare-machine command

Use 64-bit PowerShell 7, preferably Run as Administrator for complete local account/task enumeration. Keep Docker, MarketBrain and the gateway running. Load the original marketbrain-admin administrator PPK in Pageant (not the gateway key), entering its passphrase only in Pageant. No PuTTY commands needed.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\TestPaytmUnattendedHealthPreflight.ps1' `
  -EvidencePath 'C:\MarketBrainData\Review\paytm-live-publication-20261115-033221-87b397d980604582bf192a89d35bceab.json'
```

Type HEALTH-CHECK when prompted in PowerShell. At completion review Pageant key cleanup and type KEY-REVIEWED. Share the ONE paytm-unattended-preflight JSON. Expected UNATTENDED_HEALTH_PREFLIGHT_PASSED_INSTALLATION_PENDING; findings require review, not account deletion. No rebuild/restart required.

G1/G2 100%, G3 80%, G4-G6 0%; 14/30 = 46.7%. This is accepted Paytm checkpoint coverage, not whole-project completion.
