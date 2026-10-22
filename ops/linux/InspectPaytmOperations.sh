#!/usr/bin/env bash
# Read-only operational snapshot. No package refresh, service changes or broker calls.
# Sourceable for offline fixtures. The Windows launcher calls po_main with a fresh ID.
po_value() {
    local value
    if value=$(timeout 20s "$@" 2>/dev/null) && [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf UNKNOWN
    fi
}
po_hash() {
    local actual
    actual=$(po_value sha256sum -- "$1")
    if [ "$actual" = UNKNOWN ]; then printf UNKNOWN
    elif [ "${actual%% *}" = "$2" ]; then printf MATCH
    else printf MISMATCH; fi
}
po_field() {
    # Reject multiline/unexpected command output rather than including it in evidence.
    if [[ "$2" =~ ^[A-Za-z0-9.:+_/-]{1,120}$ ]]; then printf '%s=%s\n' "$1" "$2"
    else printf '%s=UNKNOWN\n' "$1"; fi
}
po_main() (
    set -uo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local run="${1:-}" fingerprint state rows count result epoch
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || return 1
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] && [ "${SUDO_USER:-}" = marketbrain-admin ] || {
        printf 'STOP: Use the verified marketbrain-admin PuTTY session and sudo.\n'; return 1;
    }
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || {
        printf 'STOP: Host identity mismatch or unavailable; no external request made.\n'; return 1;
    }
    printf 'BEGIN_PAYTM_OPERATIONS_%s\nVERSION=1\nRUN_ID=%s\nHOST_IDENTITY=MATCH\n' "$run" "$run"
    po_field UTC_EPOCH "$(po_value date -u +%s)"
    po_field PROXY_CONFIG "$(po_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747)"
    po_field ALLOWLIST "$(po_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1)"
    po_field SERVICE_CONFIG "$(po_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2)"
    po_field SERVICE_STATE "$(po_value systemctl show marketbrain-paytm-gateway.service -p ActiveState --value)"
    po_field DROPINS "$(if rows=$(timeout 10s systemctl show marketbrain-paytm-gateway.service -p DropInPaths --value 2>/dev/null); then [ -z "$rows" ] && printf NONE || printf PRESENT; else printf UNKNOWN; fi)"
    po_field RELOAD_NEEDED "$(po_value systemctl show marketbrain-paytm-gateway.service -p NeedDaemonReload --value)"
    count=UNKNOWN
    if rows=$(timeout 10s ss -H -ltn 'sport = :18888' 2>/dev/null); then
        count=$(printf '%s\n' "$rows" | awk 'NF {n++} END {print n+0}')
    fi
    po_field LISTENER_COUNT "$count"
    count=UNKNOWN
    if rows=$(timeout 10s systemctl list-units --all --plain --no-legend --no-pager 'marketbrain-tunnel-stop-*' 2>/dev/null); then
        count=$(printf '%s\n' "$rows" | awk 'NF {n++} END {print n+0}')
    fi
    po_field WATCHDOG_UNIT_COUNT "$count"
    # This observes bound VPS egress ONLY, not the application/proxy route.
    # Ignore user curl config and proxy environment; verify HTTPS, no redirects/retries.
    result=$(po_value curl -q --ipv4 --noproxy '*' --proxy '' --interface 130.250.191.137 --proto '=https' --connect-timeout 8 --max-time 15 --max-filesize 64 --fail --silent --show-error https://api.ipify.org/)
    if [[ ! "$result" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then result=UNKNOWN; fi
    po_field VPS_BOUND_PUBLIC_IPV4 "$result"
    po_field NTP_SYNCHRONIZED "$(po_value timedatectl show -p NTPSynchronized --value)"
    po_field KERNEL "$(po_value uname -r)"
    po_field SSH_VERSION "$(po_value dpkg-query -W '-f=${Version}' openssh-server)"
    po_field PROXY_VERSION "$(po_value dpkg-query -W '-f=${Version}' tinyproxy)"
    # Oldest Release metadata mtime is a cache-age clue, NOT last successful update.
    epoch=UNKNOWN
    if rows=$(timeout 10s find /var/lib/apt/lists -maxdepth 1 -type f '(' -name '*InRelease' -o -name '*Release' ')' -printf '%T@\n' 2>/dev/null) && [ -n "$rows" ]; then
        epoch=$(printf '%s\n' "$rows" | sort -n | head -1 | cut -d. -f1)
    fi
    po_field APT_OLDEST_RELEASE_EPOCH "$epoch"
    count=UNKNOWN
    # Simulation does not refresh indexes or apply changes. Counts depend on existing cache.
    if rows=$(timeout 20s apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null); then
        count=$(printf '%s\n' "$rows" | awk '/^Inst / {n++} END {print n+0}')
    fi
    po_field CACHED_UPGRADE_COUNT "$count"
    po_field REBOOT_MARKER "$(if [ -e /var/run/reboot-required ]; then printf PRESENT; else printf ABSENT; fi)"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_OPERATIONS_%s\n' "$run"
)
