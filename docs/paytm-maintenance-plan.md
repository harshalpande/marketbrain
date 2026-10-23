# Maintenance preflight and remaining Paytm acceptance

**Current E173/E174:** updates and fresh administrator login accepted in159.754s. Next [read-only restart review](paytm-restart-review.md); no repeat Apply/Collect, install or backup. Earlier retry guidance below is historical. Maintenance group1 remains open; broker/unattended activation unchanged.

**E172 current:** post-refresh candidate drift stopped installation. Follow-up plan passed, with only tzdata target2026c to2026e changed. [Reviewed r2 retry](paytm-maintenance-update.md) is next; no new preflight/backup requested. Original staging retained, fresh guards apply. All six milestone groups remain unchanged.

**Current E170/E171:** backup accepted95.89s; next [reviewed updates and postchecks](paytm-maintenance-update.md), with explicit owner acceptance of on-VPS-only recovery limits. No preflight/backup rerun. Real updates and restart review remain within batch1; no automatic reboot or gateway activation. Earlier next-step notes are historical.

**E168 accepted,2026-10-23:** owner preflight76.183s, no findings;70 identical candidates, no holds/removals,8.04GiB free. Do not rerun this plan. Owner confirmed independent browser/VNC login. Next [private backup handoff](paytm-maintenance-backup.md), not package installation. Earlier preflight instructions remain historical.

2026-10-23. E166 accepts the October22 clock snapshot:10/10 usable samples,100.465s total including human preparation, no findings. Windows was1.248-2.902s ahead of VPS; Java-minus-Windows[-0.1134,+0.0903]s. This is relative short-window screening, not automatic synchronization or quote approval. Do not repeat accepted transport/application/clock batches just to advance this plan.

## Six remaining batches before paper execution integration

These are milestones, **not a promise of six executions or zero retries**. Maintenance needs planning and apply/verification; reboot may need a post-boot checkpoint. Provider failures can add investigation. New scope must be explicit.

| Batch | Completion evidence | Dependency |
|---|---|---|
| 1. VPS maintenance | Reviewed candidates; private backup/recovery; approved update; fresh admin access and post-update verification | Updates and fresh login accepted; read-only restart review pending |
| 2. Unattended gateway | Restricted identity under exact Windows task account; pinned host/fixed destination; supervision and effective egress | Provisioning pending; never automate with unrestricted admin key |
| 3. Recovery and fail-closed operations | Network loss, duplicate start, stop/disable, wrong host/key, logoff/cold restart, no fallback/replay; time-health/drift policy | Bundle ordinary negatives, separate reboot checkpoint if necessary |
| 4. Real Paytm login | Registered callback/state/MFA exchange, expiry/revocation/relogin, secret-safe failures | Real login not accepted; check current provider documentation |
| 5. Read-only quotes | Instrument/entitlement, timestamp/freshness, reconnect/stale/rate-limit behavior | Market hours for actively updating quotes; no orders |
| 6. Combined Telegram review | ACCEPT/REJECT/expiry/replay/unauthorized cases and fresh account/quote validation |100s expiry,15s quote age,0.5% slippage,quantity1,INR5000; review only |

Then return to paper execution, not live orders. Paper fills/costs/P&L and month-long pilot are separate downstream work. Offline paper implementation need not wait for every provider test.

**Today:** one consolidated preflight, estimated5-10minutes owner time (not measured runtime). VPS command maximum240s plus5s termination grace; queries10/20s, simulation60s plus5s. No market-hours requirement. Clean reviewed result permits preparing maintenance apply/verify, not claiming all six batches complete today.

## Scope and safety

The launcher supplies a fixed current-run command for an existing verified marketbrain-admin PuTTY session. It checks host/configuration hashes, stopped proxy/listener, SSH syntax, dpkg audit, held-package count, space/inodes, reported NTP status, and cached APT simulation with exact installed/candidate versions and removal count. Findings remain explicit. No raw diagnostic stderr or arbitrary clipboard content is included in the JSON.

No clock changes, index refresh, download/install/remove, service restart, backup, reboot, credential collection, application/database access or broker activity. Only the local report is created (normal SSH/sudo audit logs may be generated). The latest accepted index refresh was E162. This cached simulation is not an executable transaction approval; future apply must refresh/revalidate before changes.

[Debian APT documents](https://manpages.debian.org/trixie/apt/apt-get.8.en.html) that simulation makes no changes and disables locking: concurrent changes can invalidate results. Keep package jobs idle.1GiB/10000-inode thresholds are screening floors, not calculated download/unpack/backup requirements or proof of space on all mounts.70 upgrade candidates are not automatically70 vulnerabilities.

Before later apply, preserve private `/etc` configuration (SSH/proxy/service), package state and relevant account/key permissions, and verify provider-console/rescue access. A configuration archive is not complete package rollback or recovery from boot failure. No provider snapshot availability is assumed. [Debian recovery guidance](https://www.debian.org/releases/trixie/release-notes/upgrading.en.html#prepare-for-recovery) informs this precaution; this is not a Debian major-version upgrade.

## Complete spare-laptop steps

1. Keep package changes/tests idle. Open normal PowerShell7 and verified marketbrain-admin PuTTY. No gateway key, Docker rebuild or tunnel start.
2. In PuTTY run `sudo -v`; enter your sudo password there only.
3. In PowerShell7 run:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\ReviewPaytmMaintenance.ps1'
```

4. Type **PLAN in PowerShell** after PuTTY sudo succeeds. Command is copied.
5. Paste into PuTTY; it runs automatically. **No START-TEST, STOP or SERVER_READY input.** Wait within the stated limit; there is no interactive input in the Bash command.
6. Copy only `BEGIN_PAYTM_MAINTENANCE_<id>` through `END_PAYTM_MAINTENANCE_<id>`, including both lines but excluding progress text. Return to PowerShell and press Enter within20minutes.
7. Share ONE `paytm-maintenance-plan-...json`. If PuTTY exits before END, return with the error copied to produce a redacted failure report; also share the non-secret visible error separately. Do not repair/retry blindly.

Clean status: `MAINTENANCE_PLAN_CAPTURED_BACKUP_AND_APPLY_PENDING` means plan captured, not updated/backed up. Findings status preserves actionable evidence.

## Verification

E167:49 PowerShell assertions including four mocked complete workflows;33 Bash assertions with external commands mocked. Covers malformed/duplicate/wrong-run/oversized receipts, encoding/version/count errors, audit/hold/space/removal/config findings, timeouts, host/user rejection, cancellation and one-file/privacy boundaries. Real Debian preflight pending; mocks are not runtime proof.
