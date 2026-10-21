# Paytm gateway: VPS-local proxy staging

E146 update: owner run X68o2U8c completed with exit0 in10seconds; all three final configuration hashes match. This transport stage is accepted and must not be rerun. Paytm root HTTP503 remains unresolved; no API/authentication readiness is claimed. Next: [separate tunnel identity](paytm-restricted-tunnel.md). The staging instructions below are historical, not an instruction to reinstall.

E144 accepts the owner's second-window screenshot: public-key/passphrase login as marketbrain-admin, sudo group membership, fresh sudo password prompt after sudo -k, and sudo whoami=root. This verifies the bounded administrator-access step, not the full installer transcript, VPS hardening, gateway or Paytm authentication. Do not repeat account creation or disable root/password access now.

E145 prepares the next bounded stage: install and test a **VPS-loopback-only** CONNECT proxy, then leave it stopped. Existing laptop/application networking is not changed.

## Target path and staged delivery

1. **This handoff:** VPS localhost proxy, exact destination restrictions, verified TLS, observed static IPv4, stop/restart and negative tests. No broker credentials. Final service stopped, not enabled at boot.
2. **Next after evidence review:** separate restricted SSH forwarding identity and private application-side tunnel endpoint. Do not reuse the unrestricted human administrator key for unattended service. Do not publish a proxy on LAN/Tailscale/public interfaces or select a whole-laptop exit node. Docker-to-Windows loopback reachability must not be assumed.
3. **Application integration:** dedicated Paytm HTTP client with explicit proxy and no DIRECT alternative, no redirects to arbitrary hosts and normal certificate/hostname checks. Validate from the actual application container, including tunnel loss/restart, DNS/IPv6, secret handling and isolation from Upstox/Telegram/PostgreSQL. Existing historical RestClient currently has no proxy; it is NOT modified or deployed in this stage. No real Paytm enablement until this gate passes.

Then real callback/token-exchange verification and read-only quotes can proceed. Telegram ACCEPT/REJECT/expiry remains review-only. An HTTPS CONNECT proxy cannot inspect encrypted order paths; application permissions and execution gates, not the proxy, prevent orders.

## Implementation and boundaries

- Debian's `tinyproxy-bin` installs only the executable, avoiding the default service/configuration supplied by the separate `tinyproxy` package. `curl` is installed if needed. Configured repositories and package-maintainer hooks are used; this is an explicit package-state change, not a read-only diagnostic. No full upgrade is requested.
- New config directory `/etc/marketbrain-paytm-gateway`, new unit `/etc/systemd/system/marketbrain-paytm-gateway.service`, private `/tmp/marketbrain-paytm-proxy-*.log` and `/run` staging lock. Existing paths/unit or occupied port stop the script. Partial failures preserve evidence; do not automatically rerun or purge packages.
- Listens on **127.0.0.1:18888 only**, accepts only local IPv4 clients, binds outgoing traffic to `130.250.191.137`. The systemd service uses DynamicUser, no capabilities, a read-only system view, AF_UNIX/AF_INET only, native syscall architecture, 96MiB memory cap and 12-client limit. No SSH, firewall, forwarding, NAT or default-route changes. This is not a general public proxy.
- Final filter matches only the CONNECT request authority `developer.paytmmoney.com:443`. Exact anchored URL-mode filtering deliberately rejects plaintext absolute URLs, lookalike names, arbitrary hosts/IP literals and alternate ports. This does NOT filter paths inside TLS. The upstream Tinyproxy 1.11.2 parser filters the CONNECT authority; runtime negative tests verify the installed binary's behavior before accepting the result.
- `api.ipify.org:443` is temporarily allowed solely to observe the proxy's public IPv4. It receives a no-credential IP lookup, not project/account data. That entry is removed before a restart and must then be rejected. The final allowlist is checked byte-for-byte. DNS occurs on the VPS; actual application-side DNS behavior remains untested.
- Public Paytm root HEAD requests verify proxy CONNECT + TLS chain/hostname + an HTTP response. Even a 401/403/404/5xx response proves neither authentication, entitlement, quote access nor service quality; the evidence says reachability only. No redirects, token exchange, account query, order or API secret is used.
- The new unit is stopped on success, and stopping is requested on failure. If stop fails, the log explicitly warns; do not use the proxy. Unit files/packages remain for review. No boot enablement, laptop tunnel or automatic restart is enabled by this handoff.

## Run once from the spare laptop

Keep existing root recovery and verified admin PuTTY sessions open. On **PowerShell**:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed. Stop here.' }
& '.\ops\windows\PreparePaytmLoopbackProxy.ps1'
```

In the **marketbrain-admin PuTTY window**, run `sudo -v` and enter the account password locally. Then paste the clipboard command; it uses `sudo -n`, so a missing/expired authorization stops without consuming the pasted script as a password. Type `STAGE` at the confirmation prompt. If authorization expired, no script starts: refresh sudo before pasting. Do not treat an actual partial stage failure as permission to retry.

The one log captures progress, commands' error output, package versions, HTTP/CONNECT statuses, public egress, final state and elapsed time. Package operations have a five-minute bound each; network probes have twenty-second bounds. No fixed completion estimate is claimed. No passwords or broker credentials should be entered into this script. Keep private/session input logging disabled.

Expected final marker:

```text
VPS_PROXY_STAGED_TESTED_STOPPED_APPLICATION_NOT_CONNECTED
STAGE_EXIT=0
```

Share the complete console output or the ONE log path's contents. The file is root-readable only; use `sudo cat` with the **exact printed path** if needed. Do not send credentials, PPK files or provider-console URLs. If anything fails, keep recovery access and share the log; no automatic reinstall, file removal or repeated checks.

## Acceptance and verification limits

Runtime batch requires: exact host/IP and unused targets; non-root loopback listener; denied arbitrary/lookalike names, wrong port, IPv4/IPv6 literals and plaintext; observed registered egress; verified Paytm TLS; restart with final filter; diagnostic host subsequently denied; stopped service/no listener; explicit-proxy request fails with connection refusal after stop; no boot enablement. The final test proves only that the **curl probe** has no direct fallback, not the future Java client.

Local tests cover generated policy, guards, simulated HTTP/TLS/errors, listener/non-root/stop validation and clipboard payload. The local Docker daemon is unavailable, so no actual Debian Tinyproxy/systemd or application-container test was run here. Runtime acceptance remains pending. No new full-roadmap or predictive-accuracy percentage is inferred.

Sources: [Debian executable-only package](https://packages.debian.org/trixie/tinyproxy-bin), [Tinyproxy configuration](https://manpages.debian.org/trixie/tinyproxy/tinyproxy.conf.5.en.html), [CONNECT filtering implementation](https://github.com/tinyproxy/tinyproxy/blob/1.11.2/src/reqs.c), [systemd isolation](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html), [Paytm SDK endpoint constants](https://github.com/paytmmoney/pyPMClient/blob/master/pmClient/constants.py).
