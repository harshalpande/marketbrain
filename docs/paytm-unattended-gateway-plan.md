# Unattended Paytm gateway: proposed design and acceptance

**Current E194, 2026-10-26:** account recovery and actual exact-account probe accepted; G2 now40%. Do not rerun account provisioning/recovery. [Next key-custody batch plan](paytm-gateway-key-custody.md) covers private encrypted input, exact-account agent custody and pinned restricted authentication; input format confirmation is outstanding before import implementation/handoff. No private key is yet imported and scheduled startup/managed VPS lifecycle/reboot recovery remain pending. Earlier immediate-next-step instructions below are historical.

2026-10-26 E192/E193: reviewed inventory confirms deleted account and retained protected old-SID storage; owner-approved [Recover batch](paytm-gateway-account.md) preserves that directory and creates/verifies fresh identity/storage without reconfiguring the Running/Automatic agent. Local tests pass; actual spare recovery remains pending. G2 stays20% until G2.2 acceptance. No key custody/task/VPS activation scope added. Earlier handoffs below are historical and superseded for this state.

2026-10-26 E189/E190: dedicated Windows account, protected storage and agent configuration now exist and passed postchecks. Exact-account verification failed at an overlength credentialed process launch. [Short-bootstrap Verify recovery](paytm-gateway-account.md) uses the existing password and preserves state.236 local assertions/17 mocked workflows plus native transport tests; real account probe still pending, G2=20%. No key import, task, managed VPS lifecycle or broker activation yet. Prior Apply handoffs are superseded for this installation.

2026-10-24 E187/E188: dedicated Windows account was not created; password confirmation stopped before mutation. [Corrected account handoff](paytm-gateway-account.md) gives specific input errors and three private attempts. No cleanup, VPS/foundation rerun or scope change. G2 remains20%; key custody/supervisor/task/lifecycle are still downstream of accepted account evidence.

2026-10-23 E185/E186: spare foundation accepted. Next [dedicated Windows account/agent provisioning](paytm-gateway-account.md), not a repeated foundation/maintenance test. Fixed Windows user `marketbrain-gateway` is distinct from the VPS identity; private owner password, standard Users membership, protected `C:\ProgramData\MarketBrainPaytmGateway`, empty-agent probe. This first install does not import a key or create supervisor/task/VPS lifecycle changes. Runtime installation pending. [Accepted percentage baseline](paytm-readiness-progress.md): G1=100%, G2=20%, other groups0%; after accepted account evidence G2 becomes40%.

2026-10-23 E183/E184: maintenance/reboot is now accepted. [Engineering foundation and spare compatibility bundle](paytm-gateway-foundation.md) implements the recovery/action policy and local process/configuration tests without provisioning or activation. Exact-account key custody, production adapters, task/VPS managed lifecycle and real logoff/boot recovery still require implementation/acceptance. Do not repeat maintenance; older prerequisite notes below are historical.

2026-10-23 E179/E180: installation accepted, restart scan found six stale services/four sessions. [Confirmed reboot/postcheck](paytm-maintenance-completion.md) is the current prerequisite, not repeat installation. VM microcode disposition remains explicit; no unattended provisioning or activation has occurred. Earlier immediate-next-step notes are historical.

2026-10-23 E177/E178: missing-scanner dependency plan accepted; [combined install and scan](paytm-scanner-install.md) next. Detached maintenance execution does not establish unattended gateway supervision or key custody. No gateway activation/login acceptance yet; restart disposition remains open.

2026-10-23 E175/E176: restart review collected clean baseline/targets but scanner is absent. [Dependency preview](paytm-scanner-plan.md) next; no unattended custody/supervision or activation accepted. Do not replay successful updates or infer restart clearance from absent reboot marker.

2026-10-23 E173/E174: reviewed updates/postchecks and fresh login accepted; [read-only restart review](paytm-restart-review.md) is next. No new unattended-key custody, supervision, login or quote readiness accepted. Do not replay maintenance updates; earlier immediate-next-step notes are historical.

2026-10-23 E172: update stopped before install on candidate drift; reviewed r2 retry is the current maintenance step. Unattended activation still blocked. [Updated handoff](paytm-maintenance-update.md).

2026-10-23 E170/E171: private backup runtime accepted; [guarded exact-version update](paytm-maintenance-update.md) and post-update/restart review next. Unattended gateway activation is still blocked. Systemd independence here is for one maintenance job, not gateway supervision or unattended custody of the administrator key.

2026-10-23 E168/E169: preflight accepted, console access owner-confirmed; [private backup](paytm-maintenance-backup.md) next. Updates and unattended activation remain pending. Do not repeat accepted maintenance/clock/route batches; backup rechecks only immediate safety conditions.

2026-10-23 E166/E167 supersedes next-step notes below: clock screen accepted10/10, no repeat now. [Maintenance preflight and six remaining batches](paytm-maintenance-plan.md) is current. Drift/automatic sync remain open before activation; no broker release implied.

E164/E165: owner manually corrected Windows; [three-clock snapshot](paytm-clock-snapshot.md) is the immediate next verification. It uses an existing admin key only for manual read-only time queries, never as unattended gateway custody. Absolute accuracy/drift policy and70 VPS updates remain unresolved. Successful snapshot alone does not authorize activation.

E162/E163 update: VPS index refresh now accepted (5s,70 candidates), corrected proxy version observed and elevation issue resolved. Windows Time OpenService access denied; resync unattempted and clock comparison unresolved. Next [Windows-only read-only service diagnosis](paytm-windows-time-access.md); no blind ACL reset or repeated VPS refresh. Review maintenance separately before activating unattended custody/services. This supersedes the older prerequisite text below, not the proposed lifecycle acceptance matrix.

E159/E160 prerequisite update: the spare reports Windows OpenSSH 9.5.4.1, agent stopped/disabled; VPS identity/configuration/IP/stopped state match. Owner authorizes investigating/correcting Windows time with VPS as provisional reference, not changing VPS time. [Combined clock/index follow-up](paytm-operations-followup.md) also corrects the collector's tinyproxy-bin lookup and captures fresh upgrade candidates. No SSH-agent/service/task provisioning has occurred.

2026-10-22 owner decision: **design unattended gateway operation before login testing**, instead of proceeding with manually unlocked initial sessions. This changes the next-stage ordering. Design below is proposed; it does not install a service, persist a private key, change the VPS's current20-minute window or enable broker login/trades. E157 remains accepted diagnostic transport evidence. E158 collects operational facts and local Windows OpenSSH capability without starting anything.

## Target and boundaries

The target is a managed transport connection that recovers from ordinary network/process interruption without PuTTY prompts. Planned cold-boot/logoff recovery must be demonstrated under the exact Windows task identity, not inferred from interactive Pageant success. Laptop sleep, loss of power/internet or the VPS being unavailable cannot be hidden: report unavailable, never direct-connect to Paytm or treat stale data as live. No new paid service is proposed.

Connectivity recovery must not restore a broker token, diagnostic ARM lease, paper-writer unlock, approval, pending trade or order authority. Actual broker login/MFA/token expiry still follow Paytm's requirements; unattended gateway does not mean unattended authentication or trading. The accepted application's startup/failure locks remain in force until a separately reviewed authenticated transport design exists.

## Proposed components

| Component | Proposed responsibility | Guard / verification needed |
|---|---|---|
| Windows gateway supervisor | One owner-scoped scheduled background process; single-instance lock; fixed local127.0.0.1:18889 forwarding to VPS127.0.0.1:18888; bounded reconnect backoff; health and last failure without secrets | Check executable/version, same task/agent identity, existing port ownership, actual process exit and upstream TLS; never wildcard listener or broad proxy |
| Windows credential custody | Candidate: Microsoft Windows OpenSSH agent under a dedicated non-admin local account, with a separately restricted gateway identity; encrypted offline backup stays outside repo | One-time private provisioning under exact account; prove access controls, logoff/reboot persistence and revocation before activation. Never remove PPK passphrase or put secrets in task arguments, environment, logs or the VPS |
| VPS proxy service | Retain non-root/loopback-only fixed-egress proxy and destination/port allowlist; reviewed systemd restart policy and boot activation for managed operation | Existing temporary test-window lifecycle is NOT reused unchanged. Capture backup/hash, rehearse rollback and administrator recovery, then apply explicit reviewed service changes |
| Application transport | Preserve explicit fixed proxy, HTTPS validation, no redirect/direct fallback; expose disconnected versus transport-ready separately from authenticated-data readiness | Transport reconnect cannot auto-arm the current diagnostic component, unlock paper writer, replay requests or submit orders |
| Health/alerts | Local status command plus bounded redacted JSON events, reconnect counts/downtime/last success/version; Telegram outage/recovery later through existing channel with deduplication | SSH keepalive alone is not endpoint health. Root503 remains unavailable API evidence, not quote readiness. No tokens or full HTTP headers/bodies in health logs |

Microsoft documents account-scoped key custody via [Windows ssh-agent](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement). This supports investigation of that candidate, not an assertion that a scheduled task or a different identity can already use the current Pageant PPK. Do not install Windows OpenSSH Server; only client/agent capability is relevant. If the installed client/agent cannot meet custody and no-interactive-session requirements, stop for a reviewed alternative rather than silently weakening key protection.

Use strict host-key verification against the accepted fingerprint, public-key-only noninteractive authentication and one fixed forwarding target. Select only the approved public identity, never all available agent keys. [OpenSSH controls](https://man.openbsd.org/ssh_config) include forwarding failure and server-alive checks, but a successfully bound listener does not prove the forwarding destination works. Recheck effective VPS restrictions with the chosen client; a client migration is not covered by earlier Plink tests.

Proposed reconnect policy:5/10/20/40/60-second backoff capped at60seconds, with a health notification after repeated failures; each connection attempt bounded. Security/configuration failures (host-key change, key denial, unexpected listener owner or altered destination) latch blocked for review, not endless retries. Cancellation must stop child processes. [systemd restart/rate-limit controls](https://www.freedesktop.org/software/systemd/man/257/systemd.service.html) apply to the proxy process independently; a deliberate disable/kill switch must survive service recovery and boot. Exact defaults need tests before deployment.

## Bundled acceptance matrix

1. **Provisioning/custody:** accepted task identity, no plaintext key export, wrong-user denial, no agent forwarding, no shell/PTY/remote forwarding, exact host pin and destination, revocation and rollback. Preserve administrator access and existing unrelated keys/tasks/services.
2. **Lifecycle/recovery:** normal startup, supervisor child exit, duplicate start, Wi-Fi interruption/restoration, VPS proxy crash/restart, graceful stop, stopped supervisor, Windows logoff and cold reboot. Schedule disruptive tests with jobs idle. Docker Desktop/application cold-boot behavior is a separate dependency: a restored tunnel is not a restored whole application.
3. **Fail-closed routing:** wrong host/key, conflicting local listener, stopped backend, blocked destination, TLS failure, missing agent credential and expired/revoked credential. No DIRECT fallback, wildcard listener, automatic account/writer unlock or approval replay.
4. **Observability:** actual first-ready time, reconnect count, outage duration, resource use, last-good/last-error state, no-secret JSON report and notification deduplication. Distinguish transport recovery from API503 or broker/token failure.
5. **Operational readiness:** review current public IP/configuration, NTP and maintenance findings; verify effective source egress via a separately reviewed bounded check, not an unannounced proxy allowlist relaxation. Test explicit disable and recovery before removing manual test-window safeguards.

Implement offline supervision/custody adapters and adversarial tests together; perform reviewed owner provisioning and one combined on-machine lifecycle/negative-case run next. Cold reboot requires a separate checkpoint if needed to preserve a single report across restart, not redoing all already accepted transport tests. Service and account changes need exact inventory-based targets and a rollback path before the owner runs them.

Only after this operational acceptance do we proceed with real Paytm callback/token lifecycle, read-only quotes and the combined Telegram review test. Live orders remain disabled and are not a prerequisite for returning to paper-account integration.
