#!/usr/bin/env bash
# Clipboard preparation prepends the sourceable identity/proxy helpers. No installs.
tw_id() { [[ "$1" =~ ^[a-f0-9]{32}$ ]]; }
tw_stop() {
    timeout 25s systemctl stop marketbrain-paytm-gateway.service || return 1
    tg_proxy_stopped || return 1
}
tw_cleanup() {
    local rc="$1"
    trap - EXIT
    if [ "$tw_owned" = yes ]; then
        if tw_stop; then
            printf 'SERVER_STOPPED=%s\n' "$tw_run"
            # Only remove this run's watchdog after a confirmed proxy stop.
            timeout 15s systemctl stop "$tw_timer.timer" "$tw_timer.service" || true
        else
            printf 'SERVER_CLEANUP_FAILED=%s; watchdog retained\n' "$tw_run"
            rc=1
        fi
    fi
    printf 'SERVER_EXIT=%s RUN=%s\n' "$rc" "$tw_run"
    return "$rc"
}
tw_work() (
    set -Eeuo pipefail
    tw_run="$1" tw_owned=no tw_timer="marketbrain-tunnel-stop-$1"
    trap 'tw_cleanup "$?"' EXIT
    trap 'printf "SERVER_ERROR line=%s command=%s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
    local fingerprint policy answer client_port extra state
    printf 'SERVER_BEGIN=%s\nUTC=' "$tw_run"; date -u '+%Y-%m-%dT%H:%M:%SZ'
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ]
    [ "${SUDO_USER:-}" = marketbrain-admin ] || { tg_stop 'Use a fresh verified marketbrain-admin session with sudo'; exit 1; }
    exec 9>/run/marketbrain-gateway-identity.lock
    flock -n 9
    fingerprint=$(ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub | awk '{print $2}')
    [ "$fingerprint" = SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI ]
    printf 'SERVER_HOST_IDENTITY_OK=%s\n' "$tw_run"
    [ -n "${SSH_CONNECTION:-}" ]
    read -r TG_CLIENT client_port TG_SERVER TG_PORT extra <<< "$SSH_CONNECTION"
    [[ "$TG_CLIENT" =~ ^[0-9a-fA-F:.]+$ && "$TG_SERVER" =~ ^[0-9a-fA-F:.]+$ && "$TG_PORT" = 22 && -z "$extra" ]]
    timeout 10s /usr/sbin/sshd -t
    timeout 10s systemctl is-active --quiet ssh.service
    policy=$(tg_effective /etc/ssh/sshd_config marketbrain-gateway)
    tg_policy "$policy"
    tg_owned /etc/ssh; tg_owned /etc/ssh/marketbrain-gateway
    tg_owned /etc/ssh/marketbrain-gateway/authorized_keys
    cmp -s /etc/ssh/marketbrain-gateway/authorized_keys <(tg_key)
    [ "$(id -Gn marketbrain-gateway)" = marketbrain-gateway ]
    [ "$(getent passwd marketbrain-gateway | awk -F: '{print $7}')" = /usr/sbin/nologin ]
    printf 'SERVER_GATEWAY_POLICY_AND_KEY_OK=%s\n' "$tw_run"
    # Existing configuration is not rewritten, and temporary IP lookup is NOT reopened.
    tg_same_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747
    tg_same_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1
    tg_same_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2
    for target in /etc/marketbrain-paytm-gateway /etc/marketbrain-paytm-gateway/proxy.conf /etc/marketbrain-paytm-gateway/allowlist /etc/systemd/system/marketbrain-paytm-gateway.service; do tg_owned "$target"; done
    state=$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service)
    [ "$state" = static ]
    state=$(systemctl show marketbrain-paytm-gateway.service -p DropInPaths --value)
    [ -z "$state" ]
    state=$(systemctl show marketbrain-paytm-gateway.service -p NeedDaemonReload --value)
    [ "$state" = no ]
    tg_proxy_stopped
    state=$(ss -H -ltn 'sport = :19889')
    [ -z "$state" ] || { tg_stop 'Remote-forward denial test port already occupied'; exit 1; }
    printf 'SERVER_REMOTE_TEST_PORT_FREE=%s\n' "$tw_run"
    printf 'SERVER_CONFIG_UNCHANGED_INITIAL_STOPPED=%s\n' "$tw_run"
    printf 'One bounded 20-minute test window. No SSH/config/firewall/credentials changes.\n'
    printf 'Type START-TEST to start the existing proxy: ' >/dev/tty
    read -r -t 180 answer </dev/tty
    [ "$answer" = START-TEST ]
    # Independent systemd watchdog survives a lost terminal. It is not boot-enabled.
    if state=$(systemctl show "$tw_timer.timer" -p LoadState --value); then :
    else [ "$?" = 1 ]; fi
    [ "$state" = not-found ]
    tw_owned=yes
    timeout 15s systemd-run --quiet --unit="$tw_timer" --on-active=20m --timer-property=AccuracySec=1s /usr/bin/systemctl stop marketbrain-paytm-gateway.service
    timeout 10s systemctl is-active --quiet "$tw_timer.timer"
    pg_start
    printf 'SERVER_READY=%s\n' "$tw_run"
    printf 'Return to Windows runner. When it asks you to stop the VPS proxy, type STOP here.\n'
    read -r -t 1200 answer </dev/tty
    [ "$answer" = STOP ]
    # EXIT trap performs stop and emits the final confirmation even on failure.
)
tw_main() (
    set -Eeuo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    umask 077
    tw_id "$1" || exit 1
    local report result start
    report=$(mktemp /tmp/marketbrain-tunnel-window-XXXXXXXX.log)
    start=$SECONDS
    set +e
    tw_work "$1" 2>&1 | tee "$report"
    result=("${PIPESTATUS[@]}")
    set -e
    printf 'SERVER_REPORT_END=%s WORKER_EXIT=%s LOG_EXIT=%s ELAPSED=%s\n' "$1" "${result[0]}" "${result[1]}" "$((SECONDS-start))" | tee -a "$report"
    printf '\nCopy the following bounded report block to the Windows clipboard when requested:\n'
    printf 'BEGIN_SERVER_REPORT_%s\n' "$1"
    cat -- "$report"
    printf 'END_SERVER_REPORT_%s\n' "$1"
    printf 'Private backup log retained: %s\n' "$report"
    [ "${result[0]}" = 0 ] && [ "${result[1]}" = 0 ]
)
