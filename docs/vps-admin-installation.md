# VPS named administrator installation and second-login acceptance

E144 update: owner's screenshot shows public-key/passphrase login, marketbrain-admin identity/sudo group, a fresh sudo password challenge and final root identity. Owner continuation accepts this bounded login/privilege gate. Full installer log is not reviewed; no broader hardening claim. Do not rerun installation. Next is [loopback gateway staging](paytm-loopback-gateway.md).

E143, 2026-10-21. Owner authorized continuation after the read-only check: root session works, named account/home absent, sudo group exists but sudo executable is absent, standard key files and public-key authentication enabled, SSH inspection exit0. Initial password denial was followed by successful login; it is not evidence about the uninstalled key. Garbled paste echo is not executed-source attestation.

## Scope and effects

Creates `marketbrain-admin`, its private home/key directory, and membership in the existing sudo group. This is a **full administrator**, not the future constrained gateway service identity. Installs sudo from configured package repositories if missing; does not run a full upgrade. Writes one private setup log under `/tmp` and a setup lock under `/run`. No existing account/key overwrite, SSH reload, password/root restriction, firewall, routing, Paytm, application or database changes are requested. Package installation changes package state and can run package-maintainer hooks; no zero-side-effect claim is made.

The owner-provided Ed25519 public-key fingerprint is `SHA256:xIUVGfImY7tqFFh+VCm/0CmcdVBYyl0fZyFL7bKIxrs`. This is NOT the server's RSA host fingerprint. The public key is included in the reviewed script; no private PPK/password is stored in Git. Before applying, ensure the PPK is passphrase-protected and the existing root session/provider console remain available.

## Handoff

On spare Windows PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\PrepareVpsAdminInstallation.ps1'
```

Paste into the existing verified root PuTTY session. Review the fingerprint/effects and type `INSTALL` when asked. No script is downloaded/executed from a remote URL. Existing account/group/path, lookup errors, unsafe parent permissions, host mismatch or unexpected selected SSH policy stop the installer. Connection-specific policy uses the current SSH source/destination and is re-evaluated after account creation, including group membership; UseDNS must remain no. No configuration policy is weakened to make the script pass.

Success is `ACCOUNT_KEY_INSTALLED_PASSWORD_AND_SECOND_LOGIN_PENDING`. At that point, separately run in the root session:

```bash
passwd marketbrain-admin
```

Enter/confirm a new unique account password privately. Characters are not echoed. This password is for the Linux account/sudo and is distinct from the PPK encryption passphrase. Do not share either or enable session input/packet logging. The installer initially leaves the account password locked; complete this step before testing login. Do not change root's password here.

## Verify a second independent session

1. Keep the original root window open. Open a NEW PuTTY session to `130.250.191.137`, SSH port22, username `marketbrain-admin`.
2. Under Connection > SSH > Auth > Credentials (older versions: Auth), choose the saved private PPK. Disable attempting authentication through Pageant for this test, so another loaded key cannot mask a problem. Keep agent forwarding disabled.
3. Check the same previously verified RSA server fingerprint `SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI`. Stop if it changes.
4. Enter the PPK passphrase locally. If asked for the SERVER account password during SSH login, stop that test rather than accepting fallback. Inspect PuTTY Event Log for successful public-key authentication; mere shell access is insufficient.
5. In the new session run:

```bash
whoami
id
sudo -k
sudo -v
sudo whoami
```

Expected first identity `marketbrain-admin`, group membership includes sudo, sudo prompts for the new Linux account password, final identity `root`. Unexpected passwordless sudo or restricted privilege output requires review; group presence alone is not acceptance. Share setup output/log plus these outputs and only the authentication-related Event Log lines. Never share credentials, PPK or provider-console session URLs. No extra report rerun is required.

## Failures and boundaries

Do not rerun after a partial failure: existing-account guards intentionally stop it. Preserve the root window and report the exact failure/log. Do not delete accounts, purge sudo, kill package managers, remove package locks or edit SSH to force success. An interrupted package installation needs separate package-state review. The setup deliberately does not attempt destructive automatic rollback.

Offline verification covers 20 guard cases, six mocked clipboard assertions and shell/PowerShell syntax. It does **not** prove Debian package installation, account creation, PAM, sudo policy or real PuTTY authentication. These remain owner-run acceptance gates. No new project-completion percentage is inferred. After second-login acceptance, plan constrained Paytm gateway egress separately; no unattended service should reuse this unrestricted administrator key.

References: [Debian account management](https://manpages.debian.org/trixie/adduser/adduser.8.en.html), [OpenSSH configuration tests and key files](https://man.openbsd.org/sshd.8), [PuTTY configuration](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter4.html).
