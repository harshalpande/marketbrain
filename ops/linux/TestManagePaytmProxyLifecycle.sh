#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/StagePaytmLoopbackProxy.sh"
source "$(dirname "$0")/ManagePaytmProxyLifecycle.sh"
checks=0
pass() { checks=$((checks+1)); }
dropin=$(gm_dropin)
for line in 'Restart=on-failure' 'RestartSec=5' 'StartLimitIntervalSec=60' 'StartLimitBurst=5' 'WantedBy=multi-user.target' 'ConditionPathExists=/etc/marketbrain-paytm-gateway/managed-enabled'; do
    grep -Fxq "$line" <<< "$dropin"; pass
done
# Entire installer is exercised in an isolated filesystem with mocked systemd/network/identity APIs.
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
sed "s|/etc/|$fixture/etc/|g;s|/root/|$fixture/root/|g;s|/run/|$fixture/run/|g" "$(dirname "$0")/ManagePaytmProxyLifecycle.sh" >"$fixture/managed.sh"
source "$fixture/managed.sh"
tg_owned() { :; }; tg_same_hash() { [ "$CASE" != hash_drift ]; }
tg_effective() { printf 'fixture-policy'; }; tg_policy() { [ "$1" = fixture-policy ]; }; tg_key() { printf 'fixture-key\n'; }
tg_proxy_stopped() { [ "$ACTIVE" = inactive ]; }
uname() { if [ "$CASE" = wrong_os ]; then printf 'Other\n'; else printf 'Linux\n'; fi; }
id() { if [ "$1" = -u ]; then printf '0\n'; else printf 'marketbrain-gateway\n'; fi; }
ssh-keygen() { printf '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI comment\n'; }
sshd() { :; }; flock() { :; }; systemd-analyze() { [ "$CASE" != unit_invalid ]; }
systemd-run() { :; }; sleep() { :; }; getent() { :; }; curl() { return 99; }
timeout() { shift; if [ "$1" = /usr/sbin/sshd ]; then return 0; fi; "$@"; }
ps() { printf '1001\n'; }
ss() {
    if [ "$ACTIVE" = active ]; then
        if [ "$CASE" = wildcard ]; then printf 'LISTEN 0 12 0.0.0.0:18888 0.0.0.0:* users:(("tinyproxy",pid=%s,fd=3))\n' "$PID_FIXTURE"
        else printf 'LISTEN 0 12 127.0.0.1:18888 0.0.0.0:* users:(("tinyproxy",pid=%s,fd=3))\n' "$PID_FIXTURE"; fi
    fi
}
pg_curl() {
    case "${!#}" in
        https://example.com:443/|https://developer.paytmmoney.com:444/) printf '403'; return 56;;
        http://developer.paytmmoney.com/) printf '403';;
        https://developer.paytmmoney.com/) if [ "$CASE" = tls_failure ]; then return 60; fi; printf '200|0|503';;
        *) return 99;;
    esac
}
systemctl() {
    local property arg
    case "$1" in
        show)
            property=''; while [ "$#" -gt 0 ]; do if [ "$1" = -p ]; then shift; property="$1"; fi; shift; done
            case "$property" in
                DropInPaths) if [ "$CASE" = unexpected_dropin ]; then printf '/unexpected.conf\n'; elif [ -f "$fixture/etc/systemd/system/marketbrain-paytm-gateway.service.d/50-managed.conf" ]; then printf '%s\n' "$fixture/etc/systemd/system/marketbrain-paytm-gateway.service.d/50-managed.conf"; fi;;
                NeedDaemonReload) printf 'no\n';;
                ActiveState) printf '%s\n' "$ACTIVE";;
                MainPID) printf '%s\n' "$PID_FIXTURE";;
                NRestarts) printf '%s\n' "$RESTARTS";;
                DynamicUser|NoNewPrivileges) printf 'yes\n';;
                ProtectSystem) printf 'strict\n';;
                Restart) printf 'on-failure\n';;
                RestartUSec) printf '5s\n';;
                StartLimitIntervalUSec) printf '1min\n';;
                StartLimitBurst) printf '5\n';;
                ConditionResult) printf '%s\n' "$CONDITION";;
                LoadState) printf 'not-found\n'; return 1;;
                *) return 99;;
            esac;;
        is-enabled) printf '%s\n' "$ENABLED"; [ "$ENABLED" != disabled ];;
        is-active) return 0;;
        list-timers) if [ "$CASE" = old_timer ]; then printf 'existing timer\n'; fi;;
        daemon-reload) ENABLED=disabled;;
        start)
            if [ -e "$fixture/etc/marketbrain-paytm-gateway/managed-enabled" ]; then ACTIVE=active; PID_FIXTURE=$((PID_FIXTURE+1)); CONDITION=yes
            elif [ "$CASE" = condition_ignored ]; then ACTIVE=active; CONDITION=yes
            else ACTIVE=inactive; CONDITION=no; fi;;
        kill) if [ "$CASE" != no_restart ]; then PID_FIXTURE=$((PID_FIXTURE+1)); RESTARTS=$((RESTARTS+1)); fi;;
        disable) ACTIVE=inactive; ENABLED=disabled;;
        enable) ENABLED=enabled;;
        stop) if [ "$CASE" = guard_stop_failure ]; then return 1; fi;;
        *) printf 'Unexpected systemctl %s\n' "$*" >&2; return 99;;
    esac
}
for CASE in success wrong_os unexpected_dropin hash_drift old_timer unit_invalid wildcard no_restart condition_ignored tls_failure guard_stop_failure; do
    printf 'Managed-service fixture: %s\n' "$CASE"
    rm -rf -- "$fixture/etc" "$fixture/root" "$fixture/run"
    mkdir -p "$fixture/etc/systemd/system" "$fixture/etc/marketbrain-paytm-gateway" "$fixture/etc/ssh/marketbrain-gateway" "$fixture/root" "$fixture/run"
    for path in "$fixture/etc/systemd/system/marketbrain-paytm-gateway.service" "$fixture/etc/marketbrain-paytm-gateway/proxy.conf" "$fixture/etc/marketbrain-paytm-gateway/allowlist"; do printf 'fixture\n' >"$path"; done
    tg_key >"$fixture/etc/ssh/marketbrain-gateway/authorized_keys"
    ACTIVE=inactive ENABLED=static PID_FIXTURE=1000 RESTARTS=0 CONDITION=no
    export SUDO_USER=marketbrain-admin SSH_CONNECTION='192.0.2.1 1234 130.250.191.137 22'
    # A separate bash invocation preserves errexit inside gm_work even when parent examines its exit.
    # Do not use 'if gm_work': that suppresses errexit throughout nested function bodies.
    set +e
    output=$(set -e; gm_work 0123456789abcdef0123456789abcdef)
    rc=$?
    set -e
    if [ "$CASE" = success ]; then
        if [ "$rc" != 0 ]; then printf '%s\n' "$output"; exit 1; fi; pass
        grep -q '"success":true' <<< "$output"; pass
        grep -q '"httpStatus":503' <<< "$output"; pass
        grep -q '"crashRestartVerified":true,"disableVerified":true,"conditionBlocksStart":true' <<< "$output"; pass
        [ -e "$fixture/etc/marketbrain-paytm-gateway/managed-enabled" ]; pass
    else
        if [ "$rc" = 0 ]; then printf 'Unexpected success for %s\n%s\n' "$CASE" "$output"; exit 1; fi; pass
        grep -q '"success":false' <<< "$output"; pass
        [ ! -e "$fixture/etc/marketbrain-paytm-gateway/managed-enabled" ]; pass
        grep -q '"bootEnabled":false,"finalRunning":false' <<< "$output"; pass
    fi
    grep -q '"credentialsUsed":false,"ordersEnabled":false' <<< "$output"; pass
done
printf 'PASS: %s assertions across 11 mocked managed-service workflows. No real VPS/systemd/network changes.\n' "$checks"
