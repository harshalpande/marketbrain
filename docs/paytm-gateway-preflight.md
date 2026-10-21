# Paytm VPS gateway: identity check before configuration

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
