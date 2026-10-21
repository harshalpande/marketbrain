#!/usr/bin/env bash
# Offline policy/output tests. Never executes pg_run, package operations or the service.
set -eu
source "$(dirname "$0")/StagePaytmLoopbackProxy.sh"
checks=0
pass() { checks=$((checks+1)); }
reject() { if "$@" >/dev/null 2>&1; then printf 'Unexpected success: %s\n' "$*"; exit 1; fi; pass; }
contains() { [[ "$1" == *"$2"* ]] || { printf 'Missing expected text: %s\n' "$2"; exit 1; }; pass; }
filter=$(pg_filter final)
printf '%s\n' developer.paytmmoney.com:443 | grep -Eq "$filter"; pass
for authority in example.com:443 developer.paytmmoney.com.invalid:443 xdeveloper.paytmmoney.com:443 developer.paytmmoney.com:80 developer.paytmmoney.com:4443 api.ipify.org:443 127.0.0.1:443 '[::1]:443' 'http://developer.paytmmoney.com/' 'https://developer.paytmmoney.com/' 'developer.paytmmoney.com:443/path' 'user@developer.paytmmoney.com:443' 'DEVELOPER.paytmmoney.com:443'; do
    if printf '%s\n' "$authority" | grep -Eq "$filter"; then printf 'Filter allowed %s\n' "$authority"; exit 1; fi
    pass
done
printf '%s\n' api.ipify.org:443 | grep -Eq "$(pg_filter diagnostic)"; pass
config=$(pg_config)
for setting in 'Listen 127.0.0.1' 'Bind 130.250.191.137' 'ConnectPort 443' 'FilterURLs On' 'FilterDefaultDeny Yes' 'FilterCaseSensitive Yes'; do contains "$config" "$setting"; done
unit=$(pg_unit)
for setting in 'DynamicUser=yes' 'RestrictAddressFamilies=AF_UNIX AF_INET' 'Restart=no' 'NoNewPrivileges=yes' 'MemoryMax=96M'; do contains "$unit" "$setting"; done
if [[ "$unit" == *'[Install]'* || "$unit" == *AF_INET6* ]]; then exit 1; fi; pass
reject pg_absent "${BASH_SOURCE[0]}"
timeout() { printf '%s' "$load_state"; return "$load_rc"; }
load_state=not-found; load_rc=0; pg_unused_unit; pass
load_rc=1; pg_unused_unit; pass
load_rc=124; reject pg_unused_unit
load_state=loaded; load_rc=0; reject pg_unused_unit
load_state=''; load_rc=1; reject pg_unused_unit
pg_curl() { printf '%s' "$response"; return "$curl_rc"; }
response=403; curl_rc=56
pg_denied_connect fixture.invalid:443; pass
curl_rc=0; reject pg_denied_connect fixture.invalid:443
response=200; curl_rc=56; reject pg_denied_connect fixture.invalid:443
response=403; curl_rc=0; pg_denied_plaintext; pass
response=200; reject pg_denied_plaintext
response='200|0|403'; pg_paytm_tls; pass
response='200|0|200'; pg_paytm_tls; pass
response='200|60|200'; reject pg_paytm_tls
response='403|0|000'; reject pg_paytm_tls
response='200|0|000'; reject pg_paytm_tls
response='200|0|200'; curl_rc=60; reject pg_paytm_tls
response=130.250.191.137; curl_rc=0; pg_egress; pass
response=192.0.2.1; reject pg_egress
response='130.250.191.137 garbage'; reject pg_egress
response=130.250.191.137; curl_rc=28; reject pg_egress
timeout() {
    shift
    case "$1" in
        ss) if [ "$listen" != none ]; then printf 'LISTEN 0 128 %s:18888 0.0.0.0:*\n' "$listen"; fi ;;
        systemctl) case "$2" in
            start|stop) return 0 ;;
            is-active) return 0 ;;
            show) case "$4" in MainPID) printf '1234\n';; ActiveState) printf '%s\n' "$fixture_state";; *) return 1;; esac ;;
            *) return 1 ;;
        esac ;;
        *) return 1 ;;
    esac
}
ps() { printf '%s\n' "$fixture_uid"; }
listen=127.0.0.1; pg_listener; pass
listen=0.0.0.0; reject pg_listener
listen='[::]'; reject pg_listener
listen=none; reject pg_listener
listen=127.0.0.1; fixture_uid=1001; pg_start; pass
fixture_uid=0; reject pg_start
fixture_state=inactive; listen=none; pg_stop; pass
fixture_state=active; reject pg_stop
fixture_state=inactive; listen=127.0.0.1; reject pg_stop
uname() { printf 'NOT_LINUX\n'; }; reject pg_main
uname() { printf 'Linux\n'; }; id() { printf '1000\n'; }; reject pg_main
printf 'PASS: %s offline cases; no real proxy, Docker, VPS or package operations.\n' "$checks"
