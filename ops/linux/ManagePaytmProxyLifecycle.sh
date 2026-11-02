#!/usr/bin/env bash
# Composed with the reviewed tg_* and pg_* helpers. Definitions only until gm_main.
gm_dropin() {
    printf '%s\n' '[Unit]' 'ConditionPathExists=/etc/marketbrain-paytm-gateway/managed-enabled' \
        'StartLimitIntervalSec=60' 'StartLimitBurst=5' '[Service]' 'Restart=on-failure' 'RestartSec=5' \
        '[Install]' 'WantedBy=multi-user.target'
}
gm_step() { GM_STAGE="$1"; printf '[%s%%] %s; elapsed=%ss\n' "$2" "$GM_STAGE" "$((SECONDS-GM_START))"; }
gm_property() { timeout 10s systemctl show marketbrain-paytm-gateway.service -p "$1" --value; }
gm_disabled() {
    local state
    state=$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service 2>/dev/null) || [ "$?" = 1 ] || return 1
    [ "$state" = disabled ] || return 1
    [ ! -e /etc/marketbrain-paytm-gateway/managed-enabled ] || return 1
    tg_proxy_stopped
}
gm_disable() {
    rm -f -- /etc/marketbrain-paytm-gateway/managed-enabled || return 1
    timeout 25s systemctl disable --now marketbrain-paytm-gateway.service || return 1
    gm_disabled
}
gm_running() {
    local pid uid listeners
    pg_listener || return 1
    [ "$(gm_property ActiveState)" = active ] || return 1
    pid=$(gm_property MainPID) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    uid=$(ps -o uid= -p "$pid" | tr -d ' ') || return 1
    [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" != 0 ] || return 1
    listeners=$(timeout 10s ss -H -ltnp 'sport = :18888') || return 1
    [[ "$listeners" = *"pid=$pid,"* ]] || return 1
    [ "$(gm_property DynamicUser)" = yes ] && [ "$(gm_property NoNewPrivileges)" = yes ] && [ "$(gm_property ProtectSystem)" = strict ]
}
gm_effective() {
    [ "$(gm_property DropInPaths)" = /etc/systemd/system/marketbrain-paytm-gateway.service.d/50-managed.conf ] &&
    [ "$(gm_property Restart)" = on-failure ] && [ "$(gm_property RestartUSec)" = 5s ] &&
    [ "$(gm_property StartLimitIntervalUSec)" = 1min ] && [ "$(gm_property StartLimitBurst)" = 5 ] &&
    [ "$(gm_property NeedDaemonReload)" = no ]
}
gm_timer_stop() {
    local state
    timeout 15s systemctl stop "$GM_TIMER.timer" || return 1
    state=$(systemctl show "$GM_TIMER.service" -p LoadState --value 2>/dev/null) || [ "$?" = 1 ] || return 1
    if [ "$state" != not-found ]; then timeout 15s systemctl stop "$GM_TIMER.service" || return 1; fi
}
gm_cleanup() {
    local rc="$1"
    trap - EXIT HUP INT TERM
    if [ "$GM_OWNED" = true ] && [ "$GM_SUCCESS" != true ]; then
        if gm_disable; then
            GM_CLEANUP=true; GM_BOOT=false; GM_RUNNING=false
            # A watchdog is removed only after a confirmed persistent stop.
            gm_timer_stop || GM_CLEANUP=false
        else GM_CLEANUP=false; fi
    fi
    if [ "$rc" != 0 ]; then GM_SUCCESS=false; fi
    printf 'BEGIN_MANAGED_REPORT_%s\n' "$GM_RUN"
    printf '{"version":1,"runId":"%s","success":%s,"stage":"%s","exitCode":%s,"failureLine":%s,"elapsedSeconds":%s,"baselineVerified":%s,"backupVerified":%s,"effectivePolicyVerified":%s,"crashRestartVerified":%s,"disableVerified":%s,"conditionBlocksStart":%s,"tlsVerified":%s,"httpStatus":%s,"denialsVerified":%s,"bootEnabled":%s,"finalRunning":%s,"cleanupPassed":%s,"credentialsUsed":false,"ordersEnabled":false}\n' \
        "$GM_RUN" "$GM_SUCCESS" "$GM_STAGE" "$rc" "$GM_LINE" "$((SECONDS-GM_START))" "$GM_BASELINE" "$GM_BACKUP" "$GM_POLICY" "$GM_CRASH" "$GM_DISABLE" "$GM_CONDITION" "$GM_TLS" "$GM_HTTP" "$GM_DENIALS" "$GM_BOOT" "$GM_RUNNING" "$GM_CLEANUP"
    printf 'END_MANAGED_REPORT_%s\n' "$GM_RUN"
    return "$rc"
}
gm_work() (
    set -Eeuo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    umask 077
    GM_RUN="$1" GM_START=$SECONDS GM_STAGE=PREFLIGHT GM_LINE=0 GM_OWNED=false GM_SUCCESS=false GM_CLEANUP=true
    GM_BASELINE=false GM_BACKUP=false GM_POLICY=false GM_CRASH=false GM_DISABLE=false GM_CONDITION=false GM_TLS=false GM_HTTP=0 GM_DENIALS=false GM_BOOT=false GM_RUNNING=false
    GM_TIMER="marketbrain-managed-guard-$GM_RUN"
    trap 'GM_LINE=$LINENO' ERR
    trap 'exit 130' HUP INT TERM
    trap 'gm_cleanup "$?"' EXIT
    local fp client_port extra state backup directory old_pid old_restarts pid restarts i result
    [[ "$GM_RUN" =~ ^[a-f0-9]{32}$ ]]
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] && [ "${SUDO_USER:-}" = marketbrain-admin ] || return 1
    for tool in timeout flock systemctl systemd-run systemd-analyze ssh-keygen sshd sha256sum install cp cmp ss ps tr curl rm awk getent stat tee mktemp chmod sleep cat; do command -v "$tool" >/dev/null; done
    exec 9>/run/marketbrain-gateway-identity.lock; flock -n 9
    gm_step VERIFY_BASELINE 5
    fp=$(ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub | awk '{print $2}')
    [ "$fp" = SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI ]
    read -r TG_CLIENT client_port TG_SERVER TG_PORT extra <<< "${SSH_CONNECTION:-}"
    [[ "$TG_CLIENT" =~ ^[0-9a-fA-F:.]+$ && "$TG_SERVER" =~ ^[0-9a-fA-F:.]+$ && "$TG_PORT" = 22 && -z "$extra" ]]
    timeout 10s /usr/sbin/sshd -t
    timeout 10s systemctl is-active --quiet ssh.service
    tg_policy "$(tg_effective /etc/ssh/sshd_config marketbrain-gateway)"
    tg_owned /etc/ssh/marketbrain-gateway; tg_owned /etc/ssh/marketbrain-gateway/authorized_keys
    cmp -s /etc/ssh/marketbrain-gateway/authorized_keys <(tg_key)
    [ "$(id -Gn marketbrain-gateway)" = marketbrain-gateway ]
    tg_same_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747
    tg_same_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1
    tg_same_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2
    for directory in /etc/marketbrain-paytm-gateway /etc/marketbrain-paytm-gateway/proxy.conf /etc/marketbrain-paytm-gateway/allowlist /etc/systemd/system/marketbrain-paytm-gateway.service; do tg_owned "$directory"; done
    [ "$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service)" = static ]
    [ -z "$(gm_property DropInPaths)" ] && [ "$(gm_property NeedDaemonReload)" = no ] || return 1
    tg_proxy_stopped
    [ -z "$(timeout 10s systemctl list-timers --all --no-legend --plain 'marketbrain-tunnel-stop-*' 'marketbrain-managed-guard-*')" ]
    directory=/etc/systemd/system/marketbrain-paytm-gateway.service.d
    pg_absent "$directory"; pg_absent /etc/marketbrain-paytm-gateway/managed-enabled
    GM_BASELINE=true
    gm_step BACK_UP_CONFIGURATION 20
    backup=$(mktemp -d /root/marketbrain-managed-backup-XXXXXXXX)
    for state in /etc/systemd/system/marketbrain-paytm-gateway.service /etc/marketbrain-paytm-gateway/proxy.conf /etc/marketbrain-paytm-gateway/allowlist; do
        cp --preserve=mode,ownership,timestamps -- "$state" "$backup/"
        cmp -s "$state" "$backup/${state##*/}"
    done
    GM_BACKUP=true; printf 'Private configuration backup: %s\n' "$backup"
    gm_step INSTALL_RESTART_POLICY 35
    # Independent fail-closed timer survives a dropped terminal. Boot enable happens only after tests.
    timeout 15s systemd-run --quiet --unit="$GM_TIMER" --on-active=5m --timer-property=AccuracySec=1s \
        /bin/sh -c 'rm -f -- /etc/marketbrain-paytm-gateway/managed-enabled; /usr/bin/systemctl disable --now marketbrain-paytm-gateway.service'
    timeout 10s systemctl is-active --quiet "$GM_TIMER.timer"
    GM_OWNED=true
    install -d -m 755 "$directory"
    gm_dropin >"$directory/50-managed.conf"; chmod 644 "$directory/50-managed.conf"
    timeout 15s systemd-analyze verify /etc/systemd/system/marketbrain-paytm-gateway.service
    timeout 15s systemctl daemon-reload
    gm_effective; GM_POLICY=true
    printf '%s\n' "$GM_RUN" >/etc/marketbrain-paytm-gateway/managed-enabled
    chmod 644 /etc/marketbrain-paytm-gateway/managed-enabled
    pg_start; gm_running
    gm_step VERIFY_CRASH_RECOVERY 50
    old_pid=$(gm_property MainPID); old_restarts=$(gm_property NRestarts)
    [[ "$old_restarts" =~ ^[0-9]+$ ]]
    timeout 10s systemctl kill --kill-whom=main --signal=KILL marketbrain-paytm-gateway.service
    for i in {1..20}; do
        pid=$(gm_property MainPID); restarts=$(gm_property NRestarts)
        if [[ "$pid" =~ ^[1-9][0-9]*$ && "$restarts" =~ ^[0-9]+$ ]] && [ "$pid" != "$old_pid" ] && [ "$restarts" -gt "$old_restarts" ] && gm_running >/dev/null 2>&1; then break; fi
        sleep 1
    done
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$restarts" =~ ^[0-9]+$ ]] && [ "$pid" != "$old_pid" ] && [ "$restarts" -gt "$old_restarts" ] || return 1
    gm_running; GM_CRASH=true
    gm_step VERIFY_PERSISTENT_DISABLE 65
    gm_disable; GM_DISABLE=true
    timeout 25s systemctl start marketbrain-paytm-gateway.service
    gm_disabled; [ "$(gm_property ConditionResult)" = no ]; GM_CONDITION=true
    printf '%s\n' "$GM_RUN" >/etc/marketbrain-paytm-gateway/managed-enabled
    chmod 644 /etc/marketbrain-paytm-gateway/managed-enabled
    pg_start; gm_running
    gm_step VERIFY_TLS_AND_DENIALS 80
    result=$(pg_curl --proto '=https' --head --output /dev/null --write-out '%{http_connect}|%{ssl_verify_result}|%{http_code}' https://developer.paytmmoney.com/)
    [[ "$result" =~ ^200\|0\|[2-5][0-9][0-9]$ ]]
    GM_HTTP="${result##*|}"; GM_TLS=true
    pg_denied_connect example.com:443
    pg_denied_connect developer.paytmmoney.com:444
    pg_denied_plaintext; GM_DENIALS=true
    gm_step ENABLE_MANAGED_BOOT 95
    timeout 15s systemctl enable marketbrain-paytm-gateway.service
    [ "$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service)" = enabled ]; GM_BOOT=true
    gm_effective; gm_running; GM_RUNNING=true
    tg_same_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747
    tg_same_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1
    timeout 10s systemctl is-active --quiet ssh.service
    gm_timer_stop
    [ "$(cat /etc/marketbrain-paytm-gateway/managed-enabled)" = "$GM_RUN" ]
    gm_running
    [ "$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service)" = enabled ]
    GM_SUCCESS=true; gm_step COMPLETE 100
)
gm_main() (
    set -euo pipefail
    [[ "${1:-}" =~ ^[a-f0-9]{32}$ ]] || exit 1
    umask 077
    local report result
    report=$(mktemp /tmp/marketbrain-managed-proxy-XXXXXXXX.log)
    set +e
    gm_work "$1" 2>&1 | tee "$report"
    result=("${PIPESTATUS[@]}")
    set -e
    printf 'Private VPS log retained: %s\nCopy BEGIN_MANAGED_REPORT through END_MANAGED_REPORT into the Windows clipboard.\n' "$report"
    [ "${result[0]}" = 0 ] && [ "${result[1]}" = 0 ]
)
