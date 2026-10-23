#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmScannerPlan.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2";exit 1; };count=$((count+1)); }
sample=$'Reading package lists...\nInst libfixture-perl (1:2.3-1+deb13u1 Debian:13/stable [amd64])\nInst needrestart (3.11-1 Debian:13/stable [all])\nConf libfixture-perl (1:2.3-1+deb13u1 Debian:13/stable [amd64])\nConf needrestart (3.11-1 Debian:13/stable [all])\nPRIVATE repository detail'
out=$(printf '%s\n' "$sample" | psp_actions)
check "$out" 'I|libfixture-perl|NOT_INSTALLED|1:2.3-1+deb13u1'
check "$out" 'I|needrestart|NOT_INSTALLED|3.11-1'
check "$out" 'C|needrestart|NOT_APPLICABLE|3.11-1'
[[ "$out" != *PRIVATE* ]] || exit 1;count=$((count+1))
check "$(printf 'Inst perl [5.40-1] (5.40-2 Debian [amd64])\n'|psp_actions)" 'I|perl|5.40-1|5.40-2'
check "$(printf 'Remv fixture [1.0]\n'|psp_actions)" 'R|fixture|1.0|NOT_APPLICABLE'
for invalid in 'Inst needrestart BAD' 'Inst bad/name (1 Debian)' 'Conf needrestart BAD' 'Remv fixture BAD' 'Inst' 'Conf' 'Remv'; do
    if printf '%s\n' "$invalid" | psp_actions >/dev/null; then exit 1;else count=$((count+1));fi
done
pr_main() { [[ "${mode:-}" != baseline ]] || return 1;printf 'BEGIN_PAYTM_RESTART_%s\nVERSION=1\nEND_PAYTM_RESTART_%s\n' "$1" "$1"; }
timeout() {
    [[ "$*" = '--kill-after=5s 60s apt-get -s -o Debug::NoLocking=1 --no-install-recommends --no-remove install needrestart' ]] || return 99
    case "${mode:-}" in
      timeout) printf 'PRIVATE exception';return 124;;
      invalid) printf 'Inst needrestart BAD\n';;
      large) printf '%070000d' 0;;
      *) printf '%s\n' "$sample";;
    esac
}
run=0123456789abcdef0123456789abcdef
for mode in clean timeout invalid large; do
    out=$(psp_main "$run")
    check "$out" "BEGIN_PAYTM_SCANNER_PLAN_$run"
    check "$out" CAPTURE_COMPLETE=yes
    [[ "$out" != *PRIVATE* ]] || exit 1;count=$((count+1))
    case "$mode" in
      clean) check "$out" SIMULATION_EXIT=0;check "$out" ACTIONS_STATE=CAPTURED
        decoded=$(printf '%s\n' "$out" | sed -n 's/^ACTIONS_B64=//p' | base64 -d);check "$decoded" 'I|needrestart|NOT_INSTALLED|3.11-1';;
      timeout) check "$out" SIMULATION_EXIT=124;;
      invalid) check "$out" ACTIONS_STATE=INVALID;check "$out" ACTIONS_B64=NONE;;
      large) check "$out" ACTIONS_STATE=TOO_LARGE;;
    esac
done
mode=baseline;if psp_main "$run" >/dev/null;then exit 1;else count=$((count+1));fi
if psp_main bad >/dev/null;then exit 1;else count=$((count+1));fi
printf 'PASS: %s Bash assertions including four mocked scanner-plan runs; no VPS/package changes.\n' "$count"
