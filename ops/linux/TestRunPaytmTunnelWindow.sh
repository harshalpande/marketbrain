#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/RunPaytmTunnelWindow.sh"
checks=0
pass() { checks=$((checks+1)); }
reject() { if "$@" >/dev/null 2>&1; then printf 'Unexpected success: %s\n' "$*"; exit 1; fi; pass; }
tw_id 0123456789abcdef0123456789abcdef; pass
for id in '' abc ABCDEF0123456789abcdef0123456789ab 'x;reboot' "$(printf 'a%.0s' {1..33})"; do reject tw_id "$id"; done
printf 'START-TEST\n' | tw_read_confirmation START-TEST 1 >/dev/null; pass
printf 'STOP\n' | tw_read_confirmation STOP 1 >/dev/null; pass
reject tw_read_confirmation START-TEST 1 <<< 'WRONG'
reject tw_read_confirmation START-TEST 1 <<< ''
reject tw_read_confirmation START-TEST 1 </dev/null
if sleep 0.2 | tw_read_confirmation START-TEST 0.05 >/dev/null 2>&1; then exit 1; fi; pass
timeout() { return 0; }; tg_proxy_stopped() { return 0; }
tw_stop; pass
timeout() { return 1; }; reject tw_stop
timeout() { return 0; }; tg_proxy_stopped() { return 1; }; reject tw_stop
# Recovery branches are mocked, not actual systemd actions.
tw_owned=no tw_run=fixture tw_timer=fixture
tw_cleanup 0 >/dev/null; pass
reject tw_cleanup 1
tw_owned=yes
tw_stop() { return 1; }; reject tw_cleanup 0
tw_stop() { return 0; }
tw_cleanup 0 >/dev/null; pass
reject tw_cleanup 1
timeout() { return 1; }
tw_cleanup 0 >/dev/null; pass # Confirmed proxy stop is safe even if timer-unit cleanup fails.
printf 'PASS: %s server-window guard/recovery assertions; no real proxy or watchdog started.\n' "$checks"
