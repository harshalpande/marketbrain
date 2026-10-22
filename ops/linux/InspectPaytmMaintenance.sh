#!/usr/bin/env bash
# Definitions only. Launcher also supplies InspectPaytmOperations.sh helpers.
# Read-only package planning: never update/install/download/restart or repair dpkg.
pm_main() (
    set -uo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local run="${1:-}" rows value fingerprint candidates=NONE count=UNKNOWN removals=UNKNOWN
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || return 1
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] && [ "${SUDO_USER:-}" = marketbrain-admin ] || return 1
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || return 1
    printf '[VPS 10%%] Identity accepted; checking current configuration and package health.\n'
    printf 'BEGIN_PAYTM_MAINTENANCE_%s\nVERSION=1\nRUN_ID=%s\nHOST_IDENTITY=MATCH\n' "$run" "$run"
    po_field PROXY_CONFIG "$(po_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747)"
    po_field ALLOWLIST "$(po_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1)"
    po_field SERVICE_CONFIG "$(po_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2)"
    po_field SERVICE_STATE "$(po_value systemctl show marketbrain-paytm-gateway.service -p ActiveState --value)"
    value=UNKNOWN
    if rows=$(timeout 10s systemctl show marketbrain-paytm-gateway.service -p DropInPaths --value 2>/dev/null); then [ -z "$rows" ] && value=NONE || value=PRESENT; fi
    po_field DROPINS "$value"
    po_field RELOAD_NEEDED "$(po_value systemctl show marketbrain-paytm-gateway.service -p NeedDaemonReload --value)"
    value=UNKNOWN
    if rows=$(timeout 10s ss -H -ltn 'sport = :18888' 2>/dev/null); then value=$(printf '%s\n' "$rows" | awk 'NF {n++} END {print n+0}'); fi
    po_field LISTENER_COUNT "$value"
    po_field SSH_CONFIG_VALID "$(if timeout 10s /usr/sbin/sshd -t >/dev/null 2>&1; then printf yes; else printf no; fi)"
    value=UNKNOWN
    if rows=$(timeout 20s dpkg --audit 2>/dev/null); then [ -z "$rows" ] && value=CLEAN || value=FINDINGS; fi
    po_field DPKG_AUDIT "$value"
    value=UNKNOWN
    if rows=$(timeout 10s apt-mark showhold 2>/dev/null); then value=$(printf '%s\n' "$rows" | awk 'NF {n++} END {print n+0}'); fi
    po_field HOLD_COUNT "$value"
    value=UNKNOWN
    if rows=$(timeout 10s df -Pk /var/cache/apt/archives 2>/dev/null); then value=$(printf '%s\n' "$rows" | awk 'NR==2 {print $4}'); fi
    po_field APT_FREE_KIB "$value"
    value=UNKNOWN
    if rows=$(timeout 10s df -Pi /var/cache/apt/archives 2>/dev/null); then value=$(printf '%s\n' "$rows" | awk 'NR==2 {print $4}'); fi
    po_field APT_FREE_INODES "$value"
    po_field NTP_SYNCHRONIZED "$(po_value timedatectl show -p NTPSynchronized --value)"
    # Simulation uses existing indexes; no refresh, downloads, locks or writes.
    value=UNKNOWN
    if rows=$(timeout --kill-after=5s 60s apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null); then
        value=0
        count=$(printf '%s\n' "$rows" | awk '/^Inst / {n++} END {print n+0}')
        removals=$(printf '%s\n' "$rows" | awk '/^Remv / {n++} END {print n+0}')
        if [ "$count" -gt 200 ]; then candidates=TOO_LARGE
        elif [ "$count" -gt 0 ]; then
            candidates=$(printf '%s\n' "$rows" | awk '/^Inst / {old=$3; new=$4; if (substr(old,1,1)=="(") {new=old;old="NOT_INSTALLED"};gsub(/[\[\]]/,"",old);sub(/^\(/,"",new);print $2 "|" old "|" new}' | base64 -w 0)
            [ "${#candidates}" -le 32768 ] || candidates=TOO_LARGE
        fi
    else value=$?; fi
    po_field SIMULATION_EXIT "$value"
    po_field UPGRADE_COUNT "$count"
    po_field REMOVAL_COUNT "$removals"
    printf 'CANDIDATES_B64=%s\n' "$candidates"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_MAINTENANCE_%s\n' "$run"
    printf '[VPS 100%%] Plan captured only. No backup, package change, restart or reboot performed.\n'
)
