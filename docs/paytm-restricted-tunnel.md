# Paytm restricted tunnel: separate client identity

## E148: owner reports installation success; evidence review pending

The owner replied "It worked as expected" after the b922159 installation handoff. Record this as owner-reported success, not as an independently reviewed installer log or explicit confirmation of every fresh-login check. **Do not rerun the installer or generate another key.** Request the existing one `/tmp/marketbrain-tunnel-identity-XXXXXXXX.log` and confirmation that the fresh administrator session returned `marketbrain-admin` and `sudo whoami` returned `root`. No need to repeat successful checks; share their existing result. [Evidence](evidence/paytm-tunnel-identity-owner-report-20261021.json).

Next combined verification scope, after that review:

| Check | Required evidence |
|---|---|
| Correct identity | Pinned server host fingerprint; separate gateway key authenticates without granting a shell |
| Allowed route | Windows-loopback-only tunnel reaches VPS127.0.0.1:18888; Paytm CONNECT/TLS observed without credentials |
| Denied routes | Shell/PTY, remote forwarding and a wrong destination explicitly denied after successful authentication; an authentication failure is not a passing restriction test |
| Proxy restrictions | Disallowed destination/port and plaintext request remain blocked through the tunnel |
| Reconnect and failure | Reconnect restores the permitted route; stopping proxy/tunnel makes the explicit-proxy request fail without direct fallback |
| Final cleanup | Test-owned tunnel closed and VPS proxy stopped; preserve unrelated SSH sessions/processes |

This matrix is a plan, not an executed batch or authorization to start the proxy now. Interactive private-key use remains on the spare laptop. Keep one consolidated report with timings, progress, per-check outcomes and cleanup state. Actual application-container routing, unattended key custody, unresolved Paytm root503 and broker authentication remain separate pending gates.

E146, 2026-10-21. [VPS proxy-stage acceptance](evidence/paytm-loopback-proxy-spare-20261021.json) reviews owner report X68o2U8c: exit0,10seconds, all three generated configuration hashes match, both proxy starts were non-root/loopback-only, expected denials passed, public egress matched130.250.191.137, diagnostic host removed/denied and final service stopped. No rerun of proxy staging or administrator setup is required.

Both root HEAD probes returned `200|0|503`: CONNECT succeeded, TLS verification passed, Paytm root returned HTTP503. This closes transport-stage criteria only. The cause of503 (root path, edge policy or provider availability) is not established. Do not claim successful authentication, entitlement or quote access, and do not retry using credentials to work around it. Actual documented read-only API behavior must be validated in the later authentication stage.

## Current handoff E147: install the separate public key and account policy

The owner supplied a new Ed25519 public key. Its decoded SSH wire record is51 bytes (11-byte algorithm name and32-byte key); fingerprint `SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI`. It differs from the accepted administrator key `SHA256:xIUVGfImY7tqFFh+VCm/0CmcdVBYyl0fZyFL7bKIxrs`. An identical key comment is harmless; the key material/fingerprint is what distinguishes them. The new private PPK/passphrase stays on the spare laptop. Its storage/passphrase protection is an owner prerequisite, not established by the public key.

**Purpose:** give the future tunnel a dedicated forwarding-only identity, instead of using a full administrator key. **Successful result:** server-side account/restriction installation, not a working application gateway. Proxy remains stopped; no credentials or trades.

On spare Windows PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\PreparePaytmTunnelIdentity.ps1'
```

Keep the current root/admin PuTTY sessions and provider console available. In the verified **marketbrain-admin** PuTTY window first run `sudo -v`, entering that Linux account password privately. Then paste the copied installer once. At the confirmation, type `INSTALL-TUNNEL`. Do not run the script in Windows or paste your PPK/passphrase into the terminal.

The guarded installer refuses pre-existing account/paths, a different host/key, custom SSH launch settings, existing Match blocks or nonstandard Includes. It verifies the actual SSH candidate using the installed daemon. It appends only a `Match User marketbrain-gateway` block to the end of the main configuration (not an early include that could change following directives' scope), with full root/admin effective-policy comparisons for the current connection. The account has no home creation, no valid password, nologin shell, only its own group and a concrete denied noninteractive sudo probe. The public key is root-owned/readable; only root may change it. Account Match settings also deny remote and Unix-socket forwarding, which key-level `permitopen` alone does not establish.

The original SSH file is retained under a new root-private `/etc/ssh/marketbrain-tunnel-backup-*/original` directory. Config replacement is same-filesystem atomic, after syntax/policy checks. SSH is **reloaded, not restarted**; root/password access is not disabled. Detected failure after replacement attempts to withdraw the exact new key and restore/reload the original configuration, only if files have not drifted. Partial account/directories and backup remain for review. This is guarded recovery, not a guarantee against power loss or a concurrent external administrator edit. Do not blindly rerun after failure. Future global SSH directives must be placed before the new trailing Match block.

Expected marker:

```text
TUNNEL_IDENTITY_INSTALLED_FRESH_ADMIN_LOGIN_AND_TUNNEL_TESTS_PENDING
```

Share only the printed `/tmp/marketbrain-tunnel-identity-XXXXXXXX.log`, not backup contents. Open a **new** administrator PuTTY connection using the **original administrator PPK**, then run:

```bash
whoami
sudo -k
sudo -v
sudo whoami
```

Expected identity `marketbrain-admin`, then `root`. Keep old sessions until this succeeds. Do not attempt a normal gateway shell login: shell/subsystem sessions are deliberately disabled. After reviewing installation and fresh-admin evidence, perform the combined allowed/denied tunnel tests using the new gateway PPK, ending with proxy/tunnel stopped. Application-container integration remains a separate unverified boundary.

Local evidence and verification limits: [E147](evidence/paytm-tunnel-identity-local-20261021.json). This developer machine has not performed an actual Debian installation/reload or new key login.

## Historical completed key-preparation handoff (do not generate another key)

The existing administrator key grants full administrative access. The tunnel must use a different key/account so it can later be revoked without losing administrative recovery. Creating another key is not repeating the administrator-login check. The private key must be generated and retained on the spare laptop, not the development machine, VPS or Git repository.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\OpenVpsAdminKeyGenerator.ps1' -Purpose Gateway
```

In PuTTYgen, generate a **new Ed25519** key; do not load the administrator PPK. Set comment `marketbrain-paytm-gateway`, enter/confirm a strong passphrase, and save as `marketbrain-paytm-gateway.ppk` in a private local folder outside repository/shared Review. Keep the original administrator PPK unchanged. Copy only the entire public-key textbox line for OpenSSH (starts `ssh-ed25519`) and share that public line. Never share either PPK or either passphrase. The launcher opens the existing tool but does not generate/save keys itself, set the comment automatically, change files or contact the VPS.

Initial tunnel verification will be interactive with a passphrase. An unattended restart/unlock policy and application-container credential custody are NOT solved by this step. Do not remove passphrases or place an administrator private key into a container to automate it.

## Server-side installation contract (prepared; VPS execution pending)

- Dedicated `marketbrain-gateway` identity: no sudo membership, password authentication, interactive shell, PTY or command sessions. Root-owned authorized-key material; no authority to edit its restrictions or the proxy configuration.
- Allow client local TCP forwarding only to exact `127.0.0.1:18888`. Explicitly deny remote forwarding/listening, arbitrary destinations, Unix-socket forwarding, agent/X11 forwarding and tunnel devices. A key-level `permitopen` alone does not establish all these restrictions; verify the effective account-specific SSH policy as well.
- Inspect existing account/path/config state; create a reviewed candidate and private backup before any scoped SSH change. Validate syntax and compare effective policies for root and marketbrain-admin before/after. Preserve existing entries/access; stop on conflicting policy. Do not broadly disable SSH/password/root access as part of tunnel setup.
- Install only the new public key after confirming it differs from the administrator key. No unattended service or app-wide network changes in the first tunnel test. Keep root/admin sessions and provider recovery available.
- Batch verification: valid tunnel, denied shell/PTY/remote forwarding/wrong target, correct host-key pinning, no LAN/public proxy listener, stopped tunnel refusal and reconnect. Finish with tunnel/proxy stopped until acceptance. Never confuse a refused shell with failed tunnel authentication.

## Remaining application gates

An explicit per-Paytm Java client must use the private proxy endpoint without a direct fallback; all other clients retain their current networking. Test the actual application container and its restart/DNS/IPv6 behavior. Docker-to-Windows loopback reachability is not assumed. The old historical Paytm client remains unchanged and is not cleared for real activation by these infrastructure tests. No broker tokens/orders are authorized.

The VPS apt output also reported71 packages not upgraded. This is not a count of security vulnerabilities; dependency/security updates need a separate maintenance review before credentialed operation. No blanket system upgrade is bundled with key creation.

Local verification: five mocked launcher scenarios, including Gateway purpose separation and invalid-purpose rejection, plus PowerShell syntax. No real key created locally and no SSH restrictions/tunnel installed. Package/project percentages are not inferred from these checks.

References: [PuTTY key creation and passphrases](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter8.html), [OpenSSH forwarding and account-specific controls](https://man.openbsd.org/sshd_config.5).
