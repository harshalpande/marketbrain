# Read-only VPS restart review

**Current E175/E176:** actual run77b0af7628bf4162807175c4c8eac0c3 completed33.811s with one finding: scanner UNAVAILABLE/NOT_RUN. Health/targets pass, restart needs remain unassessed. Do not repeat this unchanged script to resolve a missing tool. Next [read-only scanner dependency preview](paytm-scanner-plan.md); the steps below describe the completed screen, not the current handoff.

## Current result and purpose

E173 accepts update run `61e8afb23b9e4e73b883914330c99514`: COMPLETE/exit 0, reviewed target verification and postchecks passed, fresh administrator login owner-confirmed, 159.754 seconds. Both PuTTY sessions stayed connected. No disconnect-recovery claim or repeat installation is needed. The absent reboot marker alone does not establish that all running processes use the updated libraries.

E174 prepares this read-only review. It checks the 70 installed target versions, existing package/SSH/time/gateway conditions, cached remaining upgrade candidates, failed service names and restart needs. The gateway must remain stopped. No package refresh/install, service restart, reset-failed, reboot, broker login or order is performed. No Docker rebuild is needed.

The existing `needrestart` executable, if available, is invoked as `needrestart -b -r l`. Debian documents batch mode as non-restarting and `-r l` as list-only: [Debian manual](https://manpages.debian.org/trixie/needrestart/needrestart.1.en.html). The parser follows the [upstream batch interface](https://github.com/liske/needrestart/blob/master/README.batch.md). Missing tools, failed scans, unrecognized output and unknown kernel/microcode states remain findings; the runner does not install a tool or infer a clean result. Unknown microcode on a VM is a review item, not an automatic reboot instruction. This is a bounded screen, not a security audit or proof against scanner exclusions.

The earlier failed update unit `marketbrain-maintenance-7fb461f8bff74ee0bb15a5afed8c49bc.service` is reported separately because its pre-install stop was already reviewed. All other failed services remain findings. Nothing clears either unit state or evidence. Session/container descriptions are masked before transfer; share the one JSON, not raw private logs.

## Complete spare-laptop handoff

1. Keep other VPS package/configuration jobs idle. In the verified **marketbrain-admin PuTTY window**, run `sudo -v` and enter its password there only. Keep that window open.
2. In ordinary **PowerShell 7 on the spare laptop**, run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 first.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Stop: repository is not clean or Git failed.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Stop: expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Pull failed. Do not continue.' }
$update = 'C:\MarketBrainData\Review\paytm-maintenance-update-20261023-120511-c095592a120346c6aa9b10779c601d3f.json'
if (-not (Test-Path -LiteralPath $update -PathType Leaf)) { throw 'Accepted update report not found.' }
& '.\ops\windows\ReviewPaytmRestart.ps1' -UpdateEvidencePath $update
```

3. When **PowerShell** asks, type `REVIEW`. It copies the VPS command to your clipboard.
4. Paste it once into **PuTTY**. There is **no START-TEST or STOP prompt**. Wait for the report; maximum 300 seconds plus 5 seconds termination grace, including up to 90 seconds for the scanner.
5. In PuTTY, copy the entire block from `BEGIN_PAYTM_RESTART_<current-id>` through `END_PAYTM_RESTART_<current-id>`, including both boundary lines. Do not include shell prompts or progress text.
6. Return to **PowerShell** and press Enter within 20 minutes. Share the one `paytm-restart-review-...json` it names. No password, key, private archive or full console log is needed.

If the VPS command expires before a complete END line, do not substitute an old report or run package updates again. The runner will record capture failure; share that JSON and the non-secret visible error. This observation is not a persistent maintenance job and does not use Apply/Collect.

## Interpretation and next gate

| Result | Meaning and next step |
| --- | --- |
| `RESTART_SCREEN_NO_KNOWN_FINDINGS_UNATTENDED_PENDING` | Listed checks found no known issues. Review the evidence before closing maintenance; unattended setup/login remain separate. |
| `RESTART_REVIEW_CAPTURED_WITH_FINDINGS` | Collection completed, but a service/kernel/session issue, missing scanner, unknown state or baseline issue needs review. Not an automatic execution failure or restart authorization. |
| `REVIEW_REQUIRED` with failure | Evidence/identity/capture/parsing did not pass. Do not claim a clean system or repeat installation. |

Any necessary restart/install requires a separate scoped plan and owner approval. Maintenance remains group 1 of six; unattended gateway/key custody, recovery/time gates, Paytm login, fresh quotes and combined Telegram review follow. Live broker orders are not a prerequisite for returning to paper trading. No overall project percentage is raised by the local test pass rate.

Local coverage: 51 PowerShell assertions including five mocked runner workflows; 31 Bash assertions including five mocked collector runs; 49 PowerShell and 33 Bash maintenance regression assertions. The actual update-report hash, combined Bash payload, PowerShell handoff syntax, JSON and SVG also pass checks. These verify parsing, privacy, action boundaries, missing/failed tools, historical-versus-new failures and one-file reporting. Actual Debian restart evidence is still pending.
