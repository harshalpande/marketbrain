#!/usr/bin/env bash
# Read existing run evidence and present service state; never install/start/stop/reload.
mr_extract() {
    awk -v begin="BEGIN_MANAGED_REPORT_$2" -v end="END_MANAGED_REPORT_$2" '
      $0==begin {begins++; inside=1}
      inside {print}
      $0==end {ends++; inside=0}
      END {if(begins!=1 || ends!=1 || inside) exit 1}
    ' "$1"
}
mr_main() (
    set -euo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local original="$1" recovery="$2" file size block='' count=0 snapshot status
    [[ "$original" =~ ^[a-f0-9]{32}$ && "$recovery" =~ ^[a-f0-9]{32}$ ]]
    [ "$(id -u)" = 0 ]
    shopt -s nullglob
    local logs=(/tmp/marketbrain-managed-proxy-*.log)
    [ "${#logs[@]}" -le 100 ]
    for file in "${logs[@]}"; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        [ "$(stat -c %u -- "$file")" = 0 ] || continue
        size=$(stat -c %s -- "$file"); [ "$size" -le 1048576 ] || continue
        if grep -Fxq "BEGIN_MANAGED_REPORT_$original" "$file"; then
            count=$((count+1))
            # Keep malformed/incomplete output for diagnosis; do not reinterpret it as success.
            block=$(mr_extract "$file" "$original") || true
        fi
    done
    status=CAPTURED
    if [ "$count" != 1 ]; then status=LOG_MATCH_REVIEW; block=''; fi
    [ "${#block}" -le 16384 ]
    snapshot=$(
        printf 'UTC='; date -u +%FT%TZ
        printf '\nSERVICE_PROPERTIES\n'
        timeout 10s systemctl show marketbrain-paytm-gateway.service -p ActiveState -p SubState -p MainPID -p UnitFileState -p DropInPaths -p Restart -p ConditionResult || true
        printf '\nLISTENER\n'; timeout 10s ss -H -ltnp 'sport = :18888' || true
        printf '\nMARKER\n'
        if [ -f /etc/marketbrain-paytm-gateway/managed-enabled ] && [ ! -L /etc/marketbrain-paytm-gateway/managed-enabled ]; then
            if grep -Fxq "$original" /etc/marketbrain-paytm-gateway/managed-enabled; then printf 'matches-original-run\n'; else printf 'different-content\n'; fi
        else printf 'absent-or-unexpected-type\n'; fi
        printf '\nTIMERS\n'; timeout 10s systemctl list-timers --all --no-legend --plain 'marketbrain-managed-guard-*' || true
    )
    [ "${#snapshot}" -le 16384 ]
    printf 'BEGIN_MANAGED_RECOVERY_%s\nSTATUS=%s\nLOG_MATCH_COUNT=%s\nORIGINAL_RUN=%s\n' "$recovery" "$status" "$count" "$original"
    printf 'REPORT_BASE64='; printf '%s' "$block" | base64 -w0; printf '\n'
    printf 'SNAPSHOT_BASE64='; printf '%s' "$snapshot" | base64 -w0; printf '\n'
    printf 'END_MANAGED_RECOVERY_%s\n' "$recovery"
)
