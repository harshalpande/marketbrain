# Paytm VPS gateway: identity check before configuration

E144/E145 current: owner second-login/sudo verification is accepted. [VPS-local proxy staging](paytm-loopback-gateway.md) is next, ending stopped with no application connection. Earlier identity/baseline/account handoffs below are historical; do not repeat them.

E143 current handoff: [install the named administrator and verify a second key login](vps-admin-installation.md). Public key and targeted inspection received. No gateway/network changes are bundled with account setup. Earlier capture/key-generation actions below are historical and need not be repeated.

## Current: baseline reviewed; create the client login key

E142, 2026-10-21: the owner supplied the complete baseline result (exit0,1s). Review is recorded in [evidence](evidence/vps-baseline-review-20261021.json). Next: [create a protected administrative key locally](vps-administrative-key-setup.md), then separately install and prove a second login. Do not rerun the capture below or change SSH/password/network settings yet. No gateway readiness is inferred.

## Historical E141 baseline handoff — completed

E141, 2026-10-21: the owner-provided provider-console screenshot and PuTTY Event Log show the same 3072-bit RSA fingerprint:

```text
SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI
```

The identity check is accepted on that independent-console basis. It does not prove absence of compromise or gateway readiness. Do not regenerate keys or repeat the earlier identity steps. Do not include provider-console session URLs in shared evidence.

Next, collect local VPS observations with `ops/linux/InspectPaytmGateway.sh`. It inspects OS/resources, interface addresses/routes/listeners, TUN/forwarding state, tool availability, firewall table inventory and selected SSH settings. It changes no configuration, installs nothing, makes no broker calls and restarts nothing. The only intentional VPS filesystem write is one private report under `/tmp` (0600 from mktemp/umask077). Network addresses and ports are included, so share privately. No credentials, environment dumps or private-key contents are exported.

In spare-laptop **PowerShell**, update and copy the reviewed command:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed; stop here.' }
& '.\ops\windows\PreparePaytmGatewayBaseline.ps1'
```

This replaces your clipboard contents with the script; it does not connect to or execute on the VPS. Switch to the **verified PuTTY root session**, paste, and press Enter if needed. The quoted heredoc preserves Linux variables and avoids relying on the VNC clipboard. Do not paste it into PowerShell or the VNC paste box. If it waits at a continuation prompt without printing progress, press Ctrl+C and share the error rather than improvising delimiters.

The script prints progress and ends with `CAPTURED_REVIEW_REQUIRED`, elapsed seconds and one `/tmp/marketbrain-gateway-baseline-....log` path. Share the complete terminal output as one pasted text, or transfer that one log using your established file-transfer method. Each inspected command is limited to10 seconds plus a2-second forced-stop grace period; no unbounded service waits. Missing utilities/nonzero exits are retained for review rather than triggering installations or repairs.

Interpretation limits: nft table inventory is not a full ruleset review; iptables version is not an allow/deny policy. `sshd -T` here shows selected **base** settings, not connection-specific Match evaluation. Provider-level firewall, external port reachability, static egress, IPv6 leakage, tunnel failure behavior and actual application routing remain untested. No app-wide Tailscale exit node may be enabled based on this report.

Offline checks: Bash syntax, eight mocked command/guard/snapshot scenarios, four mocked clipboard-payload assertions, prepared-heredoc syntax and Windows rejection through stdin. No actual VPS baseline was executed locally. [Evidence](evidence/paytm-gateway-baseline-local-20261021.json).

After report review, prepare key-based administrative access with a tested second session/recovery path; only then apply reviewed gateway changes. [OpenSSH documents](https://man.openbsd.org/sshd.8) distinguish syntax/effective-configuration tests from daemon operation and explain the additional context needed for Match rules.

## Historical identity-check instructions

2026-10-21, E140. The synthetic Paytm core rehearsal is accepted; real authentication and gateway deployment are not. HosterDaddy's reply says configuration must be done inside the VPS. It supplies no host-key type or fingerprint and therefore does not close the identity gate.

## Immediate step: use the provider console

We can obtain independent evidence without another support round trip **if** the provider offers an authenticated console separate from the SSH connection under review:

1. Sign in to the known HosterDaddy HTTPS customer/VPS control panel. Check the browser has no certificate warning. Select this VPS and open its browser Console/VNC facility, if available. Do not follow an unsolicited console link or expose raw VNC publicly.
2. Log in locally in that console. Never share root/VNC passwords. If only a raw VNC IP/port is available and there is no protected console, stop and ask support for a protected console or the SSH host-key fingerprint; do not transmit credentials over an unverified VNC connection.
3. Run the following **in the provider console**, not just the previously accepted PuTTY session. This reads fingerprints from existing public-key files and does not generate or replace keys:

```bash
for key in /etc/ssh/ssh_host_*_key.pub; do
    if [ -f "$key" ]; then
        ssh-keygen -l -E sha256 -f "$key"
    fi
done
```

4. In PuTTY, open the window system menu and **Event Log**. Find the host-key type and SHA256 fingerprint used by this connection. Compare that exact type/fingerprint with the provider-console output. Multiple server key types are normal; the negotiated key must match. Share only the fingerprint lines and PuTTY host-key line, not credentials or private-key files.
5. On a missing key, mismatch or unexpected key-change warning, stop. Do not delete PuTTY's cache, blindly accept a replacement, regenerate SSH host keys or disable checking. The default file list may not cover a custom SSH configuration; inspect that separately if the negotiated key is absent.

Reading a fingerprint only over the same unverified SSH connection does **not** independently establish identity. A match also does not prove the server was never compromised; it establishes consistency with the provider-controlled console. Password rotation and safer administrative access follow the identity/recovery checks.

Official references: [PuTTY host-key verification](https://the.earth.li/~sgtatham/putty/0.83/htmldoc/Chapter2.html#gs-hostkey), [OpenSSH fingerprint display options](https://man.openbsd.org/ssh-keygen).

## After a verified match

- Capture a bounded, read-only OS/network/firewall/SSH baseline and confirm provider-console recovery works. Do not publish full environment files, private keys or broker credentials.
- Establish key-based administration and test a second session before restricting root/password access. Install supported security updates in a reviewed maintenance window; retain rollback/recovery instructions.
- Design a narrow Paytm egress path via the VPS's registered static IPv4. Tailscale may provide the private transport, but its default exit-node behavior routes general internet traffic, so selecting an exit node for the entire spare laptop is **not** authorized by this preflight. Preserve Upstox, Telegram, PostgreSQL and existing local access. [Official exit-node documentation](https://tailscale.com/docs/features/exit-nodes).
- Prove egress from the actual application-container request path, not merely a laptop browser. Test DNS/IPv4/IPv6 handling, tunnel loss, fail-closed behavior and restart recovery before real credentials are used.
- Only then implement reviewed callback ingress, credential custody and token exchange, followed by read-only Paytm quotes and combined Telegram ACCEPT/REJECT/expiry review. No broker orders are enabled.

No gateway installation, network mutation, SSH change or broker call is performed by this documentation milestone. Its next evidence is a provider-console/PuTTY fingerprint match. No additional synthetic-core rerun or Docker rebuild is needed.
