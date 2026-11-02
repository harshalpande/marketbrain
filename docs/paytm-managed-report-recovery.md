# Recover the managed proxy report without reinstalling

**Current E210, 2026-11-02:** [Managed VPS lifecycle accepted](evidence/paytm-managed-proxy-accepted-20261102.json). Original valid report proves a10-second pass;46.141-second recovery confirms running/boot-enabled loopback proxy, matching PID/marker and no guard timers. Earlier pasted JSON was corrupted; installation was not repeated. No VPS rerun or further recovery is needed. Next is Windows supervisor transport and effective application-route integration. This VPS substage is100%; full groups remain100/60/0/0/0/0 until their remaining checkpoint requirements pass. Earlier install/recovery instructions below are historical.

Historical E209,2026-11-02: the104.128-second run25659b497afb4d088bf9fbf309f791b1 failed in PaytmManagedProxy.ps1 line21 while ConvertFrom-Json decoded the copied report. The matching report boundaries had already passed. System.ArgumentException/-2147024809 is recorded, but the input JSON and detailed parser error were not retained. We cannot determine the malformed content or whether the VPS installation succeeded from this receipt.

Windows had a fresh LOCKED heartbeat from the accepted instance24e01ce286d244c18ddb1f948eb0496a, PID16704, sequence7593 before the remote step. There is no after-check and server is null. This is not evidence of an account, signing or SSH authentication failure. It is also not proof that the VPS remained unchanged. Do not repeat the managed installer or earlier recovery/account/key steps.

The collector now checkpoints a bounded matching report envelope before parsing and returns MANAGED_REPORT_INVALID_JSON for decoding failures. Regression coverage exercises malformed JSON through the whole controller and verifies that the text survives in its single JSON report. This fixes evidence loss; the original invalid content still needs recovery before its cause can be diagnosed.

## Recovery purpose

Read the original run block from root-owned, non-symlink /tmp/marketbrain-managed-proxy-*.log files, limited to100 files of at most1MiB each. Return the block without interpreting or repairing its contents, encoded for copy/paste. Also capture current service properties, listener, enable-marker relationship to the original run and remaining guard timers. No installation, start, stop, reload, enable/disable, credentials or orders are performed. The standard launcher stages a temporary private script only.

The snapshot is diagnostic, not a new acceptance test. Original success is not silently treated as current health; missing/multiple logs and malformed JSON remain review findings. Local tests:15 recovery assertions including four actual Bash extraction cases,26 controller assertions/seven mocked workflows and47 report/launcher regressions. No real VPS was contacted locally.

## Steps on the spare laptop

Use PowerShell7. Administrator mode is acceptable but this recovery does not change Windows accounts or tasks.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7.' }
$dirty = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) { throw 'Repository check failed or local changes exist. Stop and share the status.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\RecoverPaytmManagedProxyReport.ps1'
```

The failed receipt must remain at its original C:\MarketBrainData\Review path. If moved, pass its actual path with -FailedReportPath; it is verified against the reviewed SHA256. Do not regenerate the failed receipt.

1. Leave PowerShell at its REPORT-COPIED prompt. It has copied a read-only command.
2. Open the existing verified PuTTY connection to130.250.191.137 as marketbrain-admin. Run `sudo -v`, enter the VPS admin password locally, then paste the copied command.
3. Wait for BEGIN_MANAGED_RECOVERY through END_MANAGED_RECOVERY. Normally this takes seconds. There is no START-TEST prompt.
4. Copy that entire recovery block, including all encoded lines and both boundaries. Return to PowerShell, type REPORT-COPIED and press Enter.
5. Share the one printed paytm-managed-report-recovery-...json file. Expected collection status is EVIDENCE_RECOVERED_REVIEW_REQUIRED, even when the original report parses successfully. This means evidence was recovered, not that the VPS passed acceptance.

The earlier PuTTY window need not remain open; the command reads the saved log. If the VPS rebooted and /tmp logs were removed, the capture reports that limitation. No blind installation retry is supplied.

Accepted group percentages remain G1=100%, G2=60%, G3-G6=0%, delta0. Next action depends on recovered evidence: accept an intact successful batch, or repair the specific recorded server/parser failure without repeating accepted account/key work.
