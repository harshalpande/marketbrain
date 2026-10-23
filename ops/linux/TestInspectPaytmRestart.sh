#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmRestart.sh"
source "$(dirname "$0")/PaytmReviewedPackages.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2";exit 1; };count=$((count+1)); }
out=$(printf '%s\n' 'NEEDRESTART-VER: 3.11' 'NEEDRESTART-SESS: PRIVATE @ user manager' 'NEEDRESTART-CONT: PRIVATE container' 'PRIVATE arbitrary text' 'NEEDRESTART-SVC: ssh.service' | pr_nr_sanitize)
for value in 'NEEDRESTART-VER: 3.11' 'NEEDRESTART-SESS: REDACTED' 'NEEDRESTART-CONT: REDACTED' UNRECOGNIZED_OUTPUT 'NEEDRESTART-SVC: ssh.service'; do check "$out" "$value"; done
[[ "$out" != *PRIVATE* ]] || exit 1; count=$((count+1))
check "$(printf 'ssh.service loaded failed failed PRIVATE\n' | pr_units_sanitize)" ssh.service
check "$(printf 'PRIVATE/invalid loaded failed\n' | pr_units_sanitize)" UNRECOGNIZED_UNIT
timeout() { if [[ "$1" = --kill-after=* ]]; then shift; fi; shift; "$@"; }
dpkg-query() { mu_expected | awk -F'|' '{print $1 "|ii |" $3}'; }
pr_targets;count=$((count+1))
dpkg-query() { mu_expected | awk -F'|' '{print $1 "|ii |" $2}'; }
if pr_targets; then exit 1;else count=$((count+1));fi
pm_main() { [[ "${mode:-}" != identity ]] || return 1; printf 'BEGIN_PAYTM_MAINTENANCE_%s\nVERSION=1\nEND_PAYTM_MAINTENANCE_%s\n' "$1" "$1"; }
pr_targets() { [[ "${mode:-}" != targets ]]; }
command() { [[ "$*" = '-v needrestart' ]] || return 99; if [[ "${mode:-}" != missing ]]; then printf /usr/sbin/needrestart; else return 1; fi; }
systemctl() { [[ "$*" = '--failed --type=service --no-legend --plain --no-pager' ]] || return 99; [[ "${mode:-}" != units ]] || return 1; printf 'ssh.service loaded failed failed PRIVATE\n'; }
timeout() {
    if [[ "$1" = --kill-after=* ]];then shift;fi;shift
    if [[ "$1" = /usr/sbin/needrestart ]]; then
        [[ "$*" = '/usr/sbin/needrestart -b -r l' ]] || return 99
        [[ "${mode:-}" != scanner ]] || return 124
        printf 'NEEDRESTART-VER: 3.11\nNEEDRESTART-SESS: PRIVATE USER\n';return 0
    fi
    "$@"
}
run=0123456789abcdef0123456789abcdef
for mode in clean missing targets scanner units; do
    out=$(pr_main "$run")
    check "$out" CAPTURE_COMPLETE=yes
    [[ "$out" != *PRIVATE* ]] || exit 1;count=$((count+1))
    nr=$(printf '%s\n' "$out"|sed -n 's/^NEEDRESTART_B64=//p')
    if [[ "$nr" != NONE ]];then decoded=$(printf '%s' "$nr"|base64 -d);[[ "$decoded" != *PRIVATE* ]] || exit 1;count=$((count+1));fi
    case "$mode" in missing) check "$out" NEEDRESTART_STATE=UNAVAILABLE;check "$out" NEEDRESTART_EXIT=NOT_RUN;; targets) check "$out" TARGETS_VERIFIED=NO;; scanner) check "$out" NEEDRESTART_EXIT=124;; units) check "$out" FAILED_UNITS_EXIT=1;; clean) check "$out" NEEDRESTART_EXIT=0;; esac
done
mode=identity;if pr_main "$run" >/dev/null;then exit 1;else count=$((count+1));fi
if pr_main bad >/dev/null;then exit 1;else count=$((count+1));fi
printf 'PASS: %s Bash assertions including five mocked collector runs; no VPS/restart commands executed.\n' "$count"
