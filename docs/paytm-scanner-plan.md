# Missing restart scanner: dependency preview

**Current E177/E178:** actual preview accepted51.727s, six new packages with matching configuration actions, no upgrades/removals/findings. Do not repeat the preview unchanged. Next [controlled scanner installation and scan](paytm-scanner-install.md); the preview steps below are historical. Actual installation/restart clearance remains pending.

## Accepted result and remaining gap

E175 accepts the owner's restart report `77b0af7628bf4162807175c4c8eac0c3`, completed in **33.811 seconds** without a capture failure. All70 reviewed installed targets matched; package database/SSH checks passed, NTP was synchronized, gateway configuration matched and the gateway remained inactive with no listener. Cached simulation reported zero updates/removals. No unexpected failed services were reported; the previously reviewed failed maintenance unit remains visible separately.

The one finding is `RESTART_SCANNER_UNAVAILABLE_OR_FAILED`, specifically **UNAVAILABLE / NOT_RUN**. This is not a failed package installation. Restart needs remain unassessed; empty service/session/container counts are not evidence of no stale processes. An absent reboot marker does not close that gap. E173 update acceptance stands; do not repeat the70-package installation or clear old evidence.

## Why this preview comes next

Debian's [needrestart package](https://packages.debian.org/trixie/needrestart) checks daemons after library upgrades and has dependencies and APT hooks. We must see the actual VPS dependency plan before deciding to install it. This runner uses cached APT simulation with `--no-install-recommends` and `--no-remove`, as documented in the [APT manual](https://manpages.debian.org/trixie/apt/apt-get.8.en.html). It does not refresh indexes, download, install, configure packages, restart services or activate the gateway.

The report captures proposed package names and exact old/new versions, configuration pairings and simulation exit. Existing-package changes, removals, missing scanner candidate, inconsistent configuration actions, malformed or excessive output remain findings. The expected absent scanner is excluded only from **installation-plan screening**; it stays recorded as unassessed in the nested restart review. No plan status authorizes installation or certifies package origins. Later apply preparation must review the actual versions/origins/dependencies and freshness, prevent unattended restart hooks, and preserve recovery. Do not use a generic install command before that review.

The fresh baseline is a current-state guard, not a repeat of the completed upgrade. If the scanner has appeared meanwhile, the plan flags that instead of proposing a blind reinstall. All findings can be shared in one JSON; no raw repository configuration, private errors or keys are needed.

## Spare-laptop steps

1. Keep other VPS package/configuration jobs idle. In verified **marketbrain-admin PuTTY**, run `sudo -v`; enter its password there. Keep the window open.
2. In ordinary **PowerShell7 on the spare laptop**, run:

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
$restart = 'C:\MarketBrainData\Review\paytm-restart-review-20261023-123450-77b0af7628bf4162807175c4c8eac0c3.json'
if (-not (Test-Path -LiteralPath $restart -PathType Leaf)) { throw 'Accepted restart report not found.' }
& '.\ops\windows\PlanPaytmRestartScanner.ps1' -RestartEvidencePath $restart
```

3. **PowerShell:** type `PLAN` when prompted; the command is copied to your clipboard.
4. **PuTTY:** paste once. No START-TEST/STOP input. Maximum420seconds plus5seconds termination grace; no package installation occurs.
5. Copy only the complete `BEGIN_PAYTM_SCANNER_PLAN_<current-id>` through `END_PAYTM_SCANNER_PLAN_<current-id>` block, including both lines. Return to **PowerShell** and press Enter within20minutes.
6. Share the one `paytm-scanner-plan-...json` printed at completion. If no complete block appears, do not substitute an old receipt; return to PowerShell with the incomplete output to preserve a redacted capture failure and share the non-secret visible error separately.

`SCANNER_PLAN_CAPTURED_INSTALL_APPROVAL_PENDING` means a bounded new-package-only plan was captured for review, not approved or installed. `SCANNER_PLAN_CAPTURED_WITH_FINDINGS` means collection finished but scope/health/candidate issues need review. `REVIEW_REQUIRED` with failure means evidence/capture/parsing did not pass.

## Verification and next outcome

Local tests cover package/version parsing, epoch versions, upgrades/removals, mismatched/extra configuration actions, dependency limits, failed simulations, malformed current-run receipts, source hash/cancellation, baseline findings, one-file output and privacy.51 PowerShell assertions/five mocked runner workflows and34 Bash assertions/four mocked collectors pass, plus51 PowerShell/31 Bash restart-review regression assertions. Actual source hash, combined payload/handoff syntax, JSON and SVG validation pass. Actual VPS simulation is pending; this is not Debian runtime proof.

After plan review and explicit installation approval, the next bundle should install only the reviewed scanner/dependencies and run the restart screen in the same controlled operation where feasible. Any actual service restart/reboot remains separately reviewed. Unattended gateway, login, quote and Telegram stages remain downstream. This is closure of the missing-tool finding inside maintenance group1, not a new trading feature or whole-project percentage increase.
