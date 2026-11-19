#!/usr/bin/env bash
# Diagnostic only: fixed public HTTPS root, no credentials, no service changes.
# Source defines functions; the handoff explicitly invokes mb_upstream_main.
mb_upstream_sample() {
    local route="$1" output rc=0 connect=0 verify=0 http=0 seconds=0 valid=false healthy=false
    local args=(-q --silent --show-error --connect-timeout 4 --max-time 6
        --max-redirs 0 --head --output /dev/null
        --write-out '%{http_connect}|%{ssl_verify_result}|%{http_code}|%{time_total}')
    case "$route" in
        PROXY) args+=(--proxy http://127.0.0.1:18888 --noproxy '') ;;
        DIRECT) args+=(--proxy '' --noproxy '*') ;;
        *) return 2 ;;
    esac
    output=$(timeout 8s curl "${args[@]}" https://developer.paytmmoney.com/ 2>/dev/null) || rc=$?
    if [[ "$output" =~ ^([0-9]{3})\|([0-9]{1,10})\|([0-9]{3})\|([0-9]{1,5}\.[0-9]{1,6})$ ]]; then
        connect=$((10#${BASH_REMATCH[1]})); verify=$((10#${BASH_REMATCH[2]}))
        http=$((10#${BASH_REMATCH[3]})); seconds=${BASH_REMATCH[4]}; valid=true
        if [ "$rc" = 0 ] && [ "$verify" = 0 ] && [ "$http" -ge 200 ] && [ "$http" -le 599 ]; then
            if { [ "$route" = PROXY ] && [ "$connect" = 200 ]; } || { [ "$route" = DIRECT ] && [ "$connect" = 0 ]; }; then healthy=true; fi
        fi
    fi
    # Numeric fields only; never include stderr, response headers, banners or bodies.
    printf '{"route":"%s","curlExit":%s,"metricsParsed":%s,"connectStatus":%s,"tlsVerifyCode":%s,"httpStatus":%s,"seconds":%s,"tlsResponse":%s}' \
        "$route" "$rc" "$valid" "$connect" "$verify" "$http" "$seconds" "$healthy"
}
mb_upstream_service() {
    local state='UNKNOWN'
    state=$(timeout 5s systemctl show marketbrain-paytm-gateway.service -p ActiveState --value 2>/dev/null) || state=UNKNOWN
    case "$state" in active|inactive|failed|activating|deactivating) ;; *) state=UNKNOWN ;; esac
    printf '%s' "$state"
}
mb_upstream_main() (
    set -euo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    umask 077
    for tool in curl timeout mktemp date sleep systemctl; do command -v "$tool" >/dev/null || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 1; }; done
    local correlation="${1:-}" pairs="${2:-30}"
    [[ "$correlation" =~ ^[a-f0-9]{32}$ || -z "$correlation" ]] || return 2
    [[ "$pairs" = 30 || "$pairs" = 60 ]] || return 2
    local file start service i proxy direct observed comma='' finished=false
    file=$(mktemp /tmp/paytm-upstream-XXXXXXXX.json)
    start=$SECONDS
    service=$(mb_upstream_service)
    printf '{"version":1,"comparisonId":"%s","readOnly":true,"credentialsUsed":false,"ordersEnabled":false,"serviceBefore":"%s","startedUtc":"%s","historicalCauseEstablished":false,"samples":[' "$correlation" "$service" "$(date -u +%FT%TZ)" > "$file"
    # Complete JSON on ordinary interruption between samples. SIGKILL/power loss
    # can still leave a partial file; never label that as a complete collection.
    trap 'if [ "$finished" != true ]; then printf "],\"status\":\"INTERRUPTED_REVIEW_REQUIRED\"}\n" >> "$file"; printf "\nPartial report: %s\n" "$file"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '[0%%] Comparing VPS direct and local-proxy HTTPS. No login or service changes.\n'
    if [ "$service" != active ]; then
        printf '],"status":"PROXY_NOT_ACTIVE_REVIEW_REQUIRED"}\n' >> "$file"; finished=true
        printf 'Share this ONE file: %s\n' "$file"; return 1
    fi
    printf 'VPS_CAPTURE_STARTED=%s\n' "$correlation"
    for ((i=1; i<=pairs; i++)); do
        observed=$(date -u +%FT%TZ)
        proxy=$(mb_upstream_sample PROXY)
        direct=$(mb_upstream_sample DIRECT)
        printf '%s\n{"pair":%s,"utc":"%s","proxy":%s,"direct":%s}' "$comma" "$i" "$observed" "$proxy" "$direct" >> "$file"; comma=','
        printf '[%s%%] Pair %s/%s captured; elapsed %ss.\n' "$((i*100/pairs))" "$i" "$pairs" "$((SECONDS-start))"
        if [ "$i" -lt "$pairs" ]; then sleep 10; fi
    done
    printf '],"serviceAfter":"%s","elapsedSeconds":%s,"status":"UPSTREAM_EVIDENCE_CAPTURED_REVIEW_REQUIRED"}\n' "$(mb_upstream_service)" "$((SECONDS-start))" >> "$file"
    finished=true
    printf 'Share this ONE file: %s\n' "$file"
    if [ -z "$correlation" ]; then printf 'Capture is not gateway or broker acceptance. Keep Windows gateway stopped.\n'; else printf 'Comparison captured, not readiness acceptance. Windows collector controls its own shutdown.\n'; fi
)
