# Paytm restricted tunnel: combined verification

E149, 2026-10-21. Prepared and locally tested; **spare/VPS execution pending**. This replaces the E148 request for an old installer log as the immediate next action: the batch checks the current installed key, effective policy, server identity and unchanged proxy configuration, and requires owner confirmation of a fresh administrator login/sudo. It does not retrospectively verify the installation log. Do not rerun either installer.

## Why this run

Prove that the spare laptop can reach the approved Paytm HTTPS destination through the restricted VPS identity, and that forbidden requests and stopped components fail closed. A passing result allows preparation of actual application-container routing; it does not enable login, quotes or orders.

The existing proxy is temporarily started, then stopped. SSH configuration, firewall, routes, installed packages, Windows registry and application deployment are unchanged. A run-specific systemd stop timer backs up terminal cleanup after 20 minutes. The timer is a backstop, not proof of a successful stop. A private temporary VPS log remains; only one Windows JSON needs sharing.

## Run on the spare laptop

Keep the existing administrator/root sessions and provider-console recovery available. Open a **new PuTTY session with the original administrator key**, run `whoami` and `sudo whoami`, and confirm `marketbrain-admin` and `root`. Keep that new window open.

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
3. The runner puts a generated command on the Windows clipboard. In the fresh administrator PuTTY session, type `sudo -v` first. Then paste the copied command and press Enter if needed. The command asks for `START-TEST` after checking the current server configuration. Return the exact `SERVER_READY=...` line to the waiting Windows prompt.
4. Windows runs the network checks together. At the stop prompt, type `STOP` in PuTTY. Select/copy the entire `BEGIN_SERVER_REPORT_...` through `END_SERVER_REPORT_...` block, including both marker lines. Do not copy earlier command history. Return to Windows and press Enter.
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

## Boundaries and remaining work

- Root HEAD503 may coexist with a passing transport test. It remains unresolved API-readiness evidence, not successful login or market-data entitlement.
- No external IP lookup is reopened. E146 observed fixed egress; this batch checks the unchanged binding/configuration, not a fresh independently observed public IP.
- This is Windows-to-VPS verification, not Java/Docker routing, unattended key custody or reboot acceptance.
- Only `developer.paytmmoney.com:443` is allowed. Streaming hosts/ports remain separately documented and unapproved.
- Existing OS package-maintenance review remains pending before credentialed operation. No root/password lockdown is performed here.
- [Integration and return-to-paper test roadmap](paytm-integration-verification-plan.md).

Local evidence: 97 PowerShell helper assertions (including real local child-process capture/timeout), 15 mocked Bash guard/cleanup assertions and six mocked complete-run scenarios. None prove an actual Linux systemd/SSH/proxy run. [E149 record](evidence/paytm-tunnel-verification-local-20261021.json).
