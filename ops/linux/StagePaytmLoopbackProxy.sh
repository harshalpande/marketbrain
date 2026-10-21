#!/usr/bin/env bash
# Stage only: test a VPS-local CONNECT proxy, then STOP it. No SSH or application changes.
pg_fail() { printf 'STOP: %s\n' "$*" >&2; return 1; }
pg_absent() { [ ! -e "$1" ] && [ ! -L "$1" ] || { pg_fail "Existing path: $1; review, do not overwrite"; return 1; }; }
pg_unused_unit() {
    local state rc
    if state=$(timeout 10s systemctl show -p LoadState --value marketbrain-paytm-gateway.service); then rc=0; else rc=$?; fi
    [ "$state" = not-found ] && { [ "$rc" = 0 ] || [ "$rc" = 1 ]; } || { pg_fail 'Gateway unit exists or its lookup failed'; return 1; }
}
pg_filter() {
    printf '^developer\\.paytmmoney\\.com:443$\n'
    if [ "${1:-final}" = diagnostic ]; then printf '^api\\.ipify\\.org:443$\n'; fi
}
pg_config() {
    printf '%s\n' \
        'Port 18888' 'Listen 127.0.0.1' 'Bind 130.250.191.137' \
        'Timeout 20' 'MaxClients 12' 'Allow 127.0.0.1' 'ConnectPort 443' \
        'Filter "/etc/marketbrain-paytm-gateway/allowlist"' \
        'FilterType ere' 'FilterURLs On' 'FilterCaseSensitive Yes' 'FilterDefaultDeny Yes' \
        'Syslog On' 'LogLevel Error' 'PidFile "/run/marketbrain-paytm-gateway/proxy.pid"'
}
pg_unit() {
    printf '%s\n' \
        '[Unit]' 'Description=MarketBrain staged loopback-only Paytm CONNECT proxy' 'After=network.target' \
        '[Service]' 'Type=simple' 'DynamicUser=yes' 'RuntimeDirectory=marketbrain-paytm-gateway' \
        'ExecStart=/usr/bin/tinyproxy -d -c /etc/marketbrain-paytm-gateway/proxy.conf' \
        'Restart=no' 'TimeoutStartSec=15' 'TimeoutStopSec=10' 'NoNewPrivileges=yes' \
        'ProtectSystem=strict' 'ProtectHome=yes' 'PrivateTmp=yes' 'PrivateDevices=yes' \
        'RestrictAddressFamilies=AF_UNIX AF_INET' 'SystemCallArchitectures=native' 'CapabilityBoundingSet=' \
        'RestrictSUIDSGID=yes' 'LockPersonality=yes' 'UMask=0077' \
        'MemoryMax=96M' 'TasksMax=24' 'LimitNOFILE=256'
    # Deliberately no Install section: not enabled on boot, no unattended activation.
}
pg_listener() {
    local actual
    actual=$(timeout 10s ss -H -ltn 'sport = :18888' | awk '{print $4}') || return 1
    [ "$actual" = '127.0.0.1:18888' ] || { pg_fail 'Listener missing or not exclusively IPv4 loopback'; return 1; }
}
pg_start() {
    timeout 25s systemctl start marketbrain-paytm-gateway.service || return 1
    local i pid uid
    for i in 1 2 3 4 5; do
        if timeout 10s ss -H -ltn 'sport = :18888' | grep -q '127.0.0.1:18888'; then break; fi
        sleep 1
    done
    pg_listener || return 1
    timeout 10s systemctl is-active --quiet marketbrain-paytm-gateway.service || return 1
    pid=$(timeout 10s systemctl show -p MainPID --value marketbrain-paytm-gateway.service) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    uid=$(ps -o uid= -p "$pid" | tr -d ' ') || return 1
    [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -ne 0 ] || { pg_fail 'Proxy UID missing or root'; return 1; }
    printf 'PROXY_RUNNING_NONROOT_LOOPBACK_ONLY\n'
}
pg_curl() {
    curl -q --silent --show-error --connect-timeout 8 --max-time 20 \
        --proxy http://127.0.0.1:18888 --noproxy '' \
        --cacert /etc/ssl/certs/ca-certificates.crt "$@"
}
pg_denied_connect() {
    local authority="$1" result rc
    if result=$(pg_curl --proxytunnel --head --output /dev/null \
        --write-out '%{http_connect}' "https://$authority/" 2>/dev/null); then rc=0; else rc=$?; fi
    [ "$rc" = 56 ] && [ "$result" = 403 ] || { pg_fail "Expected CONNECT rejection for $authority (exit=$rc status=$result)"; return 1; }
    printf 'DENIED_CONNECT %s (expected exit=56 status=403)\n' "$authority"
}
pg_denied_plaintext() {
    local result
    result=$(pg_curl --head --output /dev/null --write-out '%{http_code}' http://developer.paytmmoney.com/) || return 1
    [ "$result" = 403 ] || { pg_fail 'Plain HTTP was not rejected'; return 1; }
    printf 'DENIED_PLAINTEXT_HTTP\n'
}
pg_paytm_tls() {
    local result
    result=$(pg_curl --proto '=https' --head --output /dev/null \
        --write-out '%{http_connect}|%{ssl_verify_result}|%{http_code}' https://developer.paytmmoney.com/) || return 1
    [[ "$result" =~ ^200\|0\|[2-5][0-9][0-9]$ ]] || { pg_fail "HTTPS probe failed: $result"; return 1; }
    printf 'PAYTM_TLS_REACHABLE %s (root HEAD only; HTTP status is NOT authentication or entitlement)\n' "$result"
}
pg_egress() {
    local address
    address=$(pg_curl --proto '=https' --fail https://api.ipify.org/) || return 1
    [ "$address" = 130.250.191.137 ] || { pg_fail 'Observed proxy egress did not match registered IPv4'; return 1; }
    printf 'PROXY_EGRESS_IPV4_MATCH=130.250.191.137\n'
}
pg_stop() {
    timeout 25s systemctl stop marketbrain-paytm-gateway.service || return 1
    local state listeners
    state=$(timeout 10s systemctl show -p ActiveState --value marketbrain-paytm-gateway.service) || return 1
    [ "$state" = inactive ] || { pg_fail "Proxy not inactive: $state"; return 1; }
    listeners=$(timeout 10s ss -H -ltn 'sport = :18888') || return 1
    [ -z "$listeners" ] || { pg_fail 'Proxy listener remains after stop'; return 1; }
}
pg_failure_cleanup() {
    local rc="$1"
    if [ "$rc" -ne 0 ]; then
        printf 'STAGING_FAILED_REVIEW_REQUIRED exit=%s\n' "$rc" >&2
        if [ "${pg_owned:-0}" = 1 ]; then
            # Only the new dedicated unit is affected. Preserve packages/config/evidence for review.
            timeout 25s systemctl stop marketbrain-paytm-gateway.service || printf 'WARNING: stop failed; do not use proxy\n' >&2
            pg_filter final > /etc/marketbrain-paytm-gateway/allowlist
            timeout 10s systemctl show -p ActiveState -p SubState marketbrain-paytm-gateway.service || true
            timeout 10s journalctl -u marketbrain-paytm-gateway.service --no-pager -n 25 || true
        fi
        printf 'Keep admin/root access. Share this log; do not rerun, purge packages or remove locks.\n' >&2
    fi
}
pg_run() (
    set -Eeuo pipefail
    trap 'pg_failure_cleanup "$?"' EXIT
    local fingerprint answer addresses enabled existing_listeners
    pg_owned=0
    printf 'UTC: '; date -u '+%Y-%m-%dT%H:%M:%SZ'
    printf '[5%%] Validating exact VPS and unused staging targets\n'
    for tool in timeout ssh-keygen awk grep ss ip systemctl systemd-analyze stat install mktemp flock apt-get dpkg-query ps tr cmp tee chmod sha256sum; do
        command -v "$tool" >/dev/null || { pg_fail "Missing tool: $tool"; exit 1; }
    done
    grep -qx 'ID=debian' /etc/os-release
    fingerprint=$(timeout 10s ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub | awk '{print $2}')
    [ "$fingerprint" = 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI' ]
    exec 9>/run/marketbrain-paytm-stage.lock
    flock -n 9 || { pg_fail 'Another stage run is active'; exit 1; }
    pg_absent /etc/marketbrain-paytm-gateway
    pg_absent /etc/systemd/system/marketbrain-paytm-gateway.service
    pg_absent /etc/systemd/system/marketbrain-paytm-gateway.service.d
    pg_unused_unit
    existing_listeners=$(timeout 10s ss -H -ltn 'sport = :18888')
    [ -z "$existing_listeners" ] || { pg_fail 'Port 18888 is occupied'; exit 1; }
    addresses=$(timeout 10s ip -4 -o address show)
    grep -Eq ' inet 130\.250\.191\.137/' <<< "$addresses" || { pg_fail 'Registered IPv4 not assigned here'; exit 1; }
    [ -f /etc/ssl/certs/ca-certificates.crt ]
    printf '[15%%] Installs tinyproxy-bin/curl if needed; creates a new local-only service, tests then STOPS it.\n'
    printf 'No SSH, firewall, routing, laptop application, credentials or orders. Public HEAD + diagnostic IP lookup only.\n'
    printf 'Type STAGE to confirm: ' >/dev/tty
    read -r answer </dev/tty
    [ "$answer" = STAGE ] || { pg_fail 'Not confirmed'; exit 1; }
    if ! command -v tinyproxy >/dev/null || ! command -v curl >/dev/null; then
        timeout --kill-after=10s 300s apt-get -o DPkg::Lock::Timeout=30 -o Acquire::Retries=0 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o APT::Update::Error-Mode=any update
        DEBIAN_FRONTEND=noninteractive timeout --kill-after=10s 300s apt-get -o DPkg::Lock::Timeout=30 install -y --no-install-recommends --no-upgrade --no-remove tinyproxy-bin curl
    fi
    # Use distro binary, not an arbitrary PATH shim. No default tinyproxy daemon package installed.
    [ -x /usr/bin/tinyproxy ]
    dpkg-query -W -f='${Package} ${Version}\n' tinyproxy-bin curl
    printf '[35%%] Writing dedicated configuration; no existing files overwritten\n'
    pg_absent /etc/marketbrain-paytm-gateway
    pg_absent /etc/systemd/system/marketbrain-paytm-gateway.service
    pg_unused_unit
    install -d -m 755 -o root -g root /etc/marketbrain-paytm-gateway
    pg_config > /etc/marketbrain-paytm-gateway/proxy.conf
    pg_filter diagnostic > /etc/marketbrain-paytm-gateway/allowlist
    (set -o noclobber; pg_unit > /etc/systemd/system/marketbrain-paytm-gateway.service)
    chmod 644 /etc/marketbrain-paytm-gateway/proxy.conf /etc/marketbrain-paytm-gateway/allowlist /etc/systemd/system/marketbrain-paytm-gateway.service
    pg_owned=1
    timeout 20s systemd-analyze verify /etc/systemd/system/marketbrain-paytm-gateway.service
    timeout 20s systemctl daemon-reload
    pg_start
    printf '[50%%] Negative destination/method/port tests and temporary IPv4 egress probe\n'
    pg_denied_connect example.com:443
    pg_denied_connect developer.paytmmoney.com.invalid:443
    pg_denied_connect developer.paytmmoney.com:80
    pg_denied_connect 127.0.0.1:443
    pg_denied_connect '[::1]:443'
    pg_denied_plaintext
    pg_egress
    pg_paytm_tls
    printf '[70%%] Remove diagnostic allowlist entry, restart and verify final restrictions\n'
    pg_stop
    pg_filter final > /etc/marketbrain-paytm-gateway/allowlist
    pg_start
    pg_denied_connect api.ipify.org:443
    pg_denied_connect example.com:443
    pg_denied_plaintext
    pg_paytm_tls
    printf '[90%%] Stop service and verify proxy request cannot fall back directly\n'
    pg_stop
    local rc
    if pg_curl --proto '=https' --head --output /dev/null https://developer.paytmmoney.com/ 2>/dev/null; then rc=0; else rc=$?; fi
    [ "$rc" = 7 ] || { pg_fail "Expected connection refusal after stop, received exit $rc"; exit 1; }
    printf 'PROXY_STOPPED_NO_DIRECT_FALLBACK_PROBE_EXIT=7\n'
    cmp -s /etc/marketbrain-paytm-gateway/allowlist <(pg_filter final)
    enabled=$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service 2>/dev/null || true)
    [ "$enabled" = static ] || { pg_fail "Unexpected enablement: $enabled"; exit 1; }
    sha256sum /etc/marketbrain-paytm-gateway/proxy.conf /etc/marketbrain-paytm-gateway/allowlist /etc/systemd/system/marketbrain-paytm-gateway.service
    printf '[100%%] VPS_PROXY_STAGED_TESTED_STOPPED_APPLICATION_NOT_CONNECTED\n'
    printf 'No production path verified. No SSH tunnel or automatic startup enabled. No credentials, tokens, quotes or orders.\n'
)
pg_main() (
    set -Eeuo pipefail
    export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin
    umask 077
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] || { pg_fail 'Run on the verified VPS using sudo, not Windows'; exit 1; }
    local report started rc codes
    report=$(mktemp /tmp/marketbrain-paytm-proxy-XXXXXXXX.log)
    started=$SECONDS
    printf 'ONE report: %s\n' "$report"
    # Enable errexit inside the worker while retaining both pipeline statuses in the parent.
    set +e
    (set -e; pg_run) 2>&1 | tee "$report"
    codes=("${PIPESTATUS[@]}")
    rc=${codes[0]}
    if [ "$rc" = 0 ] && [ "${codes[1]}" != 0 ]; then rc=${codes[1]}; fi
    set -e
    printf 'STAGE_EXIT=%s ELAPSED_SECONDS=%s\nShare ONE log: %s\n' "$rc" "$((SECONDS-started))" "$report" | tee -a "$report"
    exit "$rc"
)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then pg_main "$@"; fi
