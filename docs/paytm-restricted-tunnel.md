# Paytm restricted tunnel: separate client identity

E146, 2026-10-21. [VPS proxy-stage acceptance](evidence/paytm-loopback-proxy-spare-20261021.json) reviews owner report X68o2U8c: exit0,10seconds, all three generated configuration hashes match, both proxy starts were non-root/loopback-only, expected denials passed, public egress matched130.250.191.137, diagnostic host removed/denied and final service stopped. No rerun of proxy staging or administrator setup is required.

Both root HEAD probes returned `200|0|503`: CONNECT succeeded, TLS verification passed, Paytm root returned HTTP503. This closes transport-stage criteria only. The cause of503 (root path, edge policy or provider availability) is not established. Do not claim successful authentication, entitlement or quote access, and do not retry using credentials to work around it. Actual documented read-only API behavior must be validated in the later authentication stage.

## Immediate handoff: new key on spare Windows

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

## Next server-side installation contract (pending public key)

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
