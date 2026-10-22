# Paytm restricted tunnel: combined verification

## Current correction E150, 2026-10-22

Owner run dbf8758ff3c24498867be577d20f7fcd passed identity/key/configuration checks but timed out at the START-TEST read (exit142,181seconds), before watchdog creation or proxy activation. A small reproduction also timed out through the redirected launcher; the owner then reported DIRECT_INPUT_OK with direct terminal input. This isolates the failing launch path, not a typing error. The exact installed sudo pseudo-terminal mechanism was not independently measured.

The corrected `FILE_WITH_TERMINAL_STDIN_V2` handoff passes the bootstrap as a safely quoted `bash -c` argument to sudo, with stdin attached to `/dev/tty`. Inside that bootstrap, a unique root-private directory receives the script; its SHA256 is verified and its mode set400 before Bash executes the file with terminal stdin. **No interactive script is fed into sudo through a here-document anymore.** The cat here-document is internal to the command argument and does not replace sudo's stdin. Installer entrypoints remain removed. The private staged file and private log are retained on the VPS for diagnosis; only one Windows JSON is shared.

Terminal presence is checked before proxy activation; actual START/STOP acknowledgements are captured in the report. Limits, host/key pinning, proxy restrictions and20-minute watchdog are unchanged. Failed bounded server evidence is preserved with `serverEvidenceVerified=false`; old reports without the new markers cannot pass the new verifier. Local checks:110 helper assertions,21 Bash confirmation/guard checks, five native Git Bash launcher checks and seven mocked workflows. Native staging tests substitute terminal/identity checks and use harmless fixture bodies; **real Linux sudo/PTY and VPS execution of this correction remain pending**. Docker API was unavailable locally; no daemon/VM was started. [Evidence](evidence/paytm-tunnel-input-repair-20261022.json).

E149, 2026-10-21. Prepared and locally tested; **spare/VPS execution pending**. This replaces the E148 request for an old installer log as the immediate next action: the batch checks the current installed key, effective policy, server identity and unchanged proxy configuration, and requires owner confirmation of a fresh administrator login/sudo. It does not retrospectively verify the installation log. Do not rerun either installer.

## Why this run

Prove that the spare laptop can reach the approved Paytm HTTPS destination through the restricted VPS identity, and that forbidden requests and stopped components fail closed. A passing result allows preparation of actual application-container routing; it does not enable login, quotes or orders.

The existing proxy is temporarily started, then stopped. SSH configuration, firewall, routes, installed packages, Windows registry and application deployment are unchanged. A run-specific systemd stop timer backs up terminal cleanup after20minutes. The timer is a backstop, not proof of a successful stop. The private staged script and temporary VPS log remain; only one Windows JSON needs sharing.

## Run on the spare laptop

Keep the existing administrator/root sessions and provider-console recovery available. Open a **new PuTTY session with the original administrator key**, run `whoami` and `sudo whoami`, and confirm `marketbrain-admin` and `root`. Keep that new window open.

If previous windows were closed, check in PuTTY before starting another run:

```bash
sudo systemctl show marketbrain-paytm-gateway.service -p ActiveState --value
sudo ss -H -ltn 'sport = :18888'
sudo systemctl list-timers --all 'marketbrain-tunnel-stop-*' --no-pager
```

Require `inactive`, no port18888 listener and no pending test timer. If different, retain the output and stop for review, rather than blindly killing processes or deleting timer units. The Windows runner independently refuses an occupied local18889 port.

Have the **separate gateway PPK** available locally, still passphrase protected. Do not upload it or paste any password/key into chat. PuTTY/Plink 0.83 or newer, Pageant, Windows curl and Get-NetTCPConnection are required. No tools are installed automatically. Unexpected PuTTY Default Settings stop the run rather than being overwritten.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\TestPaytmTunnelBundle.ps1'
```

Follow the prompts in order:

1. Confirm the fresh admin check with `ADMIN-VERIFIED`.
2. In Pageant (system-tray icon if no window opens), choose **Add Key**, load only the new gateway PPK and enter its passphrase privately. Its fingerprint is `SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI`. Confirm `KEY-READY`. An authenticated command-channel refusal is checked before starting the VPS proxy.
3. PowerShell puts a generated command on the clipboard and waits. **Leave PowerShell waiting.** In the administrator PuTTY session, manually type `sudo -v`; do not copy it, as that would overwrite the generated command. Paste the generated command with Shift+Insert and press Enter if needed. The corrected launcher prints `Private script verified: ...` and checks the current server state. At `IN THIS PUTTY WINDOW: type START-TEST...`, type `START-TEST` and press Enter **in PuTTY within180seconds**. Wait for `START-TEST accepted.` followed by `SERVER_READY=...`. Copy that actual complete output line from PuTTY into the waiting **PowerShell** prompt. Never run SERVER_READY as a PuTTY command or fabricate it from the Windows question.
4. Windows runs the network checks together. PuTTY may already show its STOP prompt: wait until **PowerShell requests the stop** before answering it. Then type `STOP` and Enter in PuTTY. Select/copy the entire `BEGIN_SERVER_REPORT_...` through `END_SERVER_REPORT_...` block, including both marker lines. Do not copy earlier command history. Return to PowerShell and **press Enter only**, without pasting; the runner reads the clipboard.
5. After the stopped-backend check, remove **only this gateway key** from Pageant's key list and confirm `KEY-REMOVED`. Keep the encrypted PPK file and unrelated loaded keys. Removal is owner-confirmed, not independently measured.

The public key selector in the repository chooses the corresponding Pageant key; it contains no secret. PuTTY documents selection of a Pageant key using a public key file with `-i`, avoiding private-key/passphrase arguments. [Official PuTTY command-line identity documentation](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter3.html#using-cmdline-identity), [Plink options](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter7.html).

## Acceptance matrix

| Group | Evidence required |
|---|---|
| Identity and configuration | Pinned SSH host fingerprint; exact gateway key; effective restriction policy; unchanged accepted proxy hashes; fresh admin owner confirmation |
| Allowed path | Exactly one owned Windows127.0.0.1 listener; Paytm CONNECT200, TLS verification0 and recorded HTTP status |
| SSH restrictions | Successful authentication followed by explicit command/PTY-requested session, wrong destination and remote-forward refusals; no output from a remote command |
| Proxy restrictions | Disallowed name, lookalike, port80, former diagnostic host and plaintext HTTP rejected |
| Recovery | Closing owned tunnel refuses the request; a fresh tunnel restores the permitted TLS path |
| Stopped backend and cleanup | VPS stop evidence; stopped proxy causes explicit connection refusal through a still-running tunnel; final owned local listener absent; gateway Pageant key removal owner-confirmed |

A timeout, failed login or arbitrary disconnect is not a passing denial. Session-channel denial prevents PTY allocation; this is not a standalone PTY negotiation test. Unknown client wording/results stop for review rather than weakening acceptance.

Success: `TUNNEL_BATCH_PASSED_APPLICATION_AND_AUTHENTICATION_PENDING`. Anything else: `REVIEW_REQUIRED`; share the JSON and do not restart/reinstall blindly. Stage and process timings, captured outputs, cleanup state and bounded server evidence are embedded. If a console closes, retain admin access and check the dedicated service is stopped before continuing; do not treat elapsed watchdog time alone as confirmation.

If PuTTY returns to `marketbrain-admin@...$` without printing SERVER_READY, the script has ended. START-TEST and STOP are prompt responses, **not Linux commands**. Type `FAILED` at the PowerShell readiness question, copy the failed current-run report block when asked, and complete the gateway-key removal prompt. A red REVIEW_REQUIRED result is expected. Do not claim KEY-REMOVED until you actually remove the gateway key from Pageant. If no complete server report was produced, retain the visible error and report that missing evidence; never substitute an older run.

## Boundaries and remaining work

- Root HEAD503 may coexist with a passing transport test. It remains unresolved API-readiness evidence, not successful login or market-data entitlement.
- No external IP lookup is reopened. E146 observed fixed egress; this batch checks the unchanged binding/configuration, not a fresh independently observed public IP.
- This is Windows-to-VPS verification, not Java/Docker routing, unattended key custody or reboot acceptance.
- Only `developer.paytmmoney.com:443` is allowed. Streaming hosts/ports remain separately documented and unapproved.
- Existing OS package-maintenance review remains pending before credentialed operation. No root/password lockdown is performed here.
- [Integration and return-to-paper test roadmap](paytm-integration-verification-plan.md).

Historical E149:97 PowerShell helper assertions,15 mocked Bash guard/cleanup assertions and six mocked complete-run scenarios did not cover actual sudo/terminal interaction. E150 adds the file-launcher/confirmation regressions described above; no local count is treated as successful VPS execution.
