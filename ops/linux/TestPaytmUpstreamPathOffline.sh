#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/TestPaytmUpstreamPath.sh"
checks=0
check() { if ! eval "$1"; then printf 'FAILED: %s\n' "$2" >&2; exit 1; fi; checks=$((checks+1)); }
# Fake curl only. No external service or network operation is made.
timeout() { shift; "$@"; }
curl() {
    [[ "$*" == *'--head'* && "$*" == *'--max-time 6'* && "$*" == *'https://developer.paytmmoney.com/'* ]]
    printf '%s' "$fixture_output"; return "$fixture_exit"
}
fixture_output='200|0|503|0.123456'; fixture_exit=0
row=$(mb_upstream_sample PROXY)
check '[[ "$row" == *'\''"tlsResponse":true'\''* ]]' PROXY_503_TLS_RESPONSE
fixture_output='000|0|503|0.123456'; row=$(mb_upstream_sample DIRECT)
check '[[ "$row" == *'\''"tlsResponse":true'\''* ]]' DIRECT_503_TLS_RESPONSE
row=$(mb_upstream_sample PROXY)
check '[[ "$row" == *'\''"tlsResponse":false'\''* ]]' PROXY_REQUIRES_CONNECT_200
fixture_output='200|0|000|6.000000'; fixture_exit=28; row=$(mb_upstream_sample PROXY)
check '[[ "$row" == *'\''"curlExit":28'\''* && "$row" == *'\''"tlsResponse":false'\''* ]]' TIMEOUT_RETAINED
fixture_output='200|20|000|0.123456'; fixture_exit=60; row=$(mb_upstream_sample PROXY)
check '[[ "$row" == *'\''"tlsVerifyCode":20'\''* && "$row" == *'\''"tlsResponse":false'\''* ]]' TLS_ERROR_RETAINED
fixture_output='SECRET unexpected response'; fixture_exit=0; row=$(mb_upstream_sample PROXY)
check '[[ "$row" != *SECRET* && "$row" == *'\''"metricsParsed":false'\''* ]]' MALFORMED_REDACTED
fixture_output=''; fixture_exit=124; row=$(mb_upstream_sample DIRECT)
check '[[ "$row" == *'\''"curlExit":124'\''* && "$row" == *'\''"tlsResponse":false'\''* ]]' OUTER_TIMEOUT_RETAINED
if mb_upstream_sample OTHER >/dev/null; then exit 1; else checks=$((checks+1)); fi
systemctl() { printf '%s' "$fixture_service"; }
sleep() { :; }
fixture_service=active; fixture_output='200|0|503|0.123456'; fixture_exit=0
log=$(mb_upstream_main)
file=$(printf '%s\n' "$log" | sed -n 's/^Share this ONE file: //p')
[[ "$file" =~ ^/tmp/paytm-upstream-[A-Za-z0-9]{8}\.json$ ]]
check '[[ $(grep -o pair "$file" | wc -l) -eq 30 ]]' THIRTY_PAIRS
check 'grep -q UPSTREAM_EVIDENCE_CAPTURED_REVIEW_REQUIRED "$file"' CAPTURE_NOT_ACCEPTANCE
rm -- "$file"
fixture_service=inactive
if log=$(mb_upstream_main); then exit 1; fi
file=$(printf '%s\n' "$log" | sed -n 's/^Share this ONE file: //p')
[[ "$file" =~ ^/tmp/paytm-upstream-[A-Za-z0-9]{8}\.json$ ]]
check 'grep -q PROXY_NOT_ACTIVE_REVIEW_REQUIRED "$file"' INACTIVE_NOT_STARTED
check '! grep -q pair "$file"' NO_PROBES_WHEN_INACTIVE
rm -- "$file"
printf 'PASS: %s offline upstream probe checks.\n' "$checks"
