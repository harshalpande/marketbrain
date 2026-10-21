# VPS administrative key setup — preserve existing access

E143 update: owner supplied the public key and confirmed PPK storage outside the repository. Do not generate another key. Next is [installation and independent second-login verification](vps-admin-installation.md), including an owner check that the PPK is passphrase protected. The creation-only instructions below are historical.

E142, 2026-10-21. Baseline capture completed in1 second with the expected host key, Debian13,708MiB available RAM,8.1GB free storage, TUN present, forwarding disabled and only TCP22 listed. Tailscale/UFW/iptables were unavailable; nft table inventory was empty. Base SSH settings allow public keys and passwords/root login, with syntax test passing. These observations do not establish external firewall policy or gateway readiness. The pasted command echo is garbled; the result section is complete. No byte-for-byte executed-script attestation is claimed.

## Current action: generate the user's key locally

This is a **client login key**, not a replacement for `/etc/ssh/ssh_host_rsa_key` or its fingerprint. Generate it on the spare Windows laptop and never send its private half to the VPS or to chat. The passphrase-protected private key stays outside Git and the shared Review folder. The public half will be used in a separate reviewed installation step.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\OpenVpsAdminKeyGenerator.ps1'
```

The helper opens an existing PuTTYgen installation visibly with Ed25519 and SHA256 selected. It neither generates a key unattended nor installs anything. If unavailable, it stops; report the message rather than downloading an arbitrary executable. Do not run this on the VPS or developer laptop as a substitute for creating the owner's key on the spare.

In PuTTYgen:

1. Confirm Ed25519 (or EdDSA with Ed25519/255-bit selection), then click Generate and follow the randomness prompt if shown.
2. Set the comment to `marketbrain-vps-admin`. Choose a strong unique key passphrase and confirm it; keep it in your password manager, not chat or a command-line argument.
3. Save the encrypted private key as `marketbrain-vps-admin.ppk` in a private local user folder outside the repository/Review directory. Do not overwrite any existing key. Keep a protected backup before later removing recovery access. Do not save without a passphrase.
4. Copy the entire single line from the public-key text box intended for OpenSSH authorized_keys. It begins `ssh-ed25519`. Share only this public line and, if desired, its SHA256 fingerprint. Do not use the differently formatted Save public key output for this handoff. Never share the `.ppk` or passphrase.

These steps follow the [official PuTTY public-key guide](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter8.html). The helper is tested with mocked process launches; no real user key was created locally by the agent.

## Installation and verification gates — not performed yet

- Review public-key syntax/fingerprint, actual AuthorizedKeysFile/Match policy and existing paths/ownership before installation. Preserve existing entries and avoid symlink/overwrite risks.
- Prepare a dedicated named administrative account with reviewed privilege/recovery policy. Do not silently grant broader permissions, alter existing accounts or overwrite key files. The exact installation command waits for the public key and target-state checks.
- Keep the working root PuTTY session and provider console available. Test a **second** independent session with the new key and intended account; verify user identity and intended administrative capability. A successful connection alone is insufficient if it fell back to a server password or a different Pageant key; inspect the client's authentication evidence.
- Do not disable password/root login, change ports/firewall or reload SSH until the intended key-only second login and recovery access are proven. Any later access restriction is a separate reviewed change.
- This interactive, passphrase-protected admin key is not an unattended gateway credential. Automated tunnelling needs a separate constrained identity/design, not an unrestricted root key.

No VPS mutation, new account, key installation, password rotation, gateway activation or Paytm API call is part of the current handoff. The next required input is the owner's **public key only**. There is no benefit in rerunning the accepted baseline or synthetic login suite for this step.
