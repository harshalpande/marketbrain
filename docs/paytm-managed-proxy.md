# Managed VPS proxy lifecycle

Current stage: E207 locked Windows supervisor accepted; E208 managed VPS implementation ready for runtime testing. The accepted Paytm groups remain **100/60/0/0/0/0**. Existing recovery, account creation and key import must not be repeated.

The accepted recovery took **36.582 seconds**. Actual background signing, advancing heartbeat, same-process duplicate start, persistent STOP across a new launch, and a final locked restart passed. Ten source hashes match the reviewed ab4ce2e Windows checkout. This establishes the locked host prerequisite; it does not establish an unattended tunnel or cold-boot recovery.

## Purpose and changes

This combined batch turns the existing manually started VPS proxy into a managed service. It backs up the three reviewed proxy configuration files, adds one systemd drop-in and one enable marker, then verifies:

1. Existing host fingerprint, restricted gateway account, configuration hashes, stopped service and absence of older test timers.
2. Effective restart policy, non-root identity and the sole IPv4 loopback listener on port18888.
3. A deliberately killed service process is replaced automatically, with an increased restart counter.
4. Removing the marker and disabling the service keeps it stopped; an explicit start is skipped while the marker is absent.
5. Certificate-validated TLS to the allowed Paytm host; unrelated host, wrong port and plaintext requests are rejected.
6. Final active service, boot enablement, unchanged proxy routing configuration and a still-locked Windows supervisor.

Success leaves the VPS proxy running and boot-enabled, listening only on127.0.0.1:18888. The Windows transport remains locked. Paytm credentials, login, quotes and orders are not tested or enabled. A root HTTP503 can demonstrate TLS transport but is not API readiness. Boot configuration is checked; an actual reboot is not performed in this batch.

The drop-in uses Restart=on-failure, five-second restart delay, a five-start/60-second limit and ConditionPathExists on the managed enable marker. The previous unit's resource and isolation limits remain in force. See the official [systemd service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) and [unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html) documentation.

## Run once on the spare laptop

Open **PowerShell7 as Administrator**, then run:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell7 as Administrator.' }
$dirty = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) { throw 'Repository check failed or local changes exist. Stop and share the status.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& '.\ops\windows\InstallPaytmManagedProxy.ps1'
```

The script reads the accepted recovery JSON from its original C:\MarketBrainData\Review path and verifies its hash. If you moved that file, provide its actual location through -SupervisorReportPath; do not rerun recovery. It also checks the existing task's fresh LOCKED heartbeat before copying the VPS command.

1. Leave PowerShell open at its REPORT-COPIED prompt.
2. Open the existing verified PuTTY connection to130.250.191.137 as **marketbrain-admin**. Run `sudo -v` and enter that account's VPS password locally.
3. Paste the command already copied by PowerShell into PuTTY. It automatically runs the whole batch, with progress messages. **There is no START-TEST or SERVER_READY exchange.** Normally allow1-3minutes; the independent fail-closed watchdog is five minutes.
4. After completion, select and copy the entire block from `BEGIN_MANAGED_REPORT_...` through `END_MANAGED_REPORT_...`, including both boundary lines and the JSON line.
5. Return to PowerShell, type **REPORT-COPIED**, then press Enter. It checks the report and the Windows supervisor again.
6. Share the single printed `paytm-managed-proxy-...json` file. Expected status: `VPS_MANAGED_PROXY_PASSED_WINDOWS_TRANSPORT_PENDING`.

Do not use the old20-minute tunnel-window installer after this managed policy is installed: its static-service/no-drop-in baseline is deliberately obsolete. No Pageant changes or Docker rebuild are required here.

## Failure and deliberate stop

The private backup under /root contains the base proxy unit, proxy.conf and allowlist; it is not a database or private-key backup. A private /tmp log preserves VPS output. The collector stores the compact server proof plus local diagnostic stage/type/line in one shareable JSON.

After a failed mutation the script requests a persistent stop. The independent five-minute watchdog also removes the enable marker and disables/stops the service if the interactive process is lost. A successful final check retires that watchdog. If a failure report or disconnect occurs, retain the report/log and review it before rerunning; existing drop-ins are intentionally rejected rather than overwritten. The final server result determines VPS state even if Windows collection later fails.

For an intentional stop after successful installation, in the admin PuTTY window run:

```bash
sudo rm -f -- /etc/marketbrain-paytm-gateway/managed-enabled
sudo systemctl disable --now marketbrain-paytm-gateway.service
sudo systemctl show marketbrain-paytm-gateway.service -p ActiveState --value
```

Expected final state: inactive. This removes only the service enable marker and preserves configuration/backups. Restarting managed operation requires a reviewed enable flow; do not improvise a new manual window.

## Acceptance boundary and next work

Local verification:47 report/launcher assertions,22 controller assertions across6 workflows and62 Bash assertions across11 workflows. Local tests cover strict report validation and mocked whole-installer success/failure sequences, including failure to restart, configuration drift, unsafe listeners, failed TLS, ignored conditions and guard cleanup failure. They do not run real systemd or touch the VPS. Runtime evidence is pending.

Next after acceptance: connect the installed Windows supervisor to the pinned restricted SSH transport and verify the effective application route. Then test the installed system's interruption, stop and real boot/logoff behavior. Only those results can close G2.4/G2.5 and advance the later groups. Login, fresh quotes and the combined review-only Telegram test follow; paper execution remains a separate milestone.
