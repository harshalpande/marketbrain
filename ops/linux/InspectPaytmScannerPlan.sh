#!/usr/bin/env bash
# Definitions only. Uses the existing restart review; no package changes.
psp_actions() {
    awk '
      function token(v) {return v ~ /^[A-Za-z0-9.+:~_-]+$/ && length(v)<=120}
      function name(v) {return v ~ /^[a-z0-9][a-z0-9.+:-]*$/ && length(v)<=120}
      /^Inst / {
        p=$2; old="NOT_INSTALLED"; v=$3
        if(substr(v,1,1)=="[") {old=v;gsub(/[\[\]]/,"",old);v=$4}
        if(substr(v,1,1)!="(")exit 2;sub(/^\(/,"",v)
        if(!name(p)||!token(old)||!token(v))exit 2
        print "I|" p "|" old "|" v;next
      }
      /^Conf / {
        p=$2;v=$3;if(substr(v,1,1)!="(")exit 2;sub(/^\(/,"",v)
        if(!name(p)||!token(v))exit 2
        print "C|" p "|NOT_APPLICABLE|" v;next
      }
      /^Remv / {
        p=$2;v=$3;if(substr(v,1,1)!="[")exit 2;gsub(/[\[\]]/,"",v)
        if(!name(p)||!token(v))exit 2
        print "R|" p "|" v "|NOT_APPLICABLE";next
      }
      /^(Inst|Conf|Remv)([[:space:]]|$)/ {exit 2}
    '
}
psp_main() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C NEEDRESTART_MODE=l
    local run="${1:-}" raw review actions=NONE state=CAPTURED result=UNKNOWN normalized
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || return 1
    printf '[VPS 10%%] Read-only scanner dependency preview and current restart baseline.\n'
    raw=$(pr_main "$run") || { printf 'STOP: restart baseline collection failed.\n'; return 1; }
    review=$(printf '%s\n' "$raw" | awk '/^BEGIN_PAYTM_RESTART_/ {capture=1} capture {print} /^END_PAYTM_RESTART_/ {capture=0}')
    [ "${#review}" -le 40000 ] || return 1
    printf '[VPS 65%%] Simulating needrestart plus required dependencies only; no refresh/download/install.\n'
    if raw=$(timeout --kill-after=5s 60s apt-get -s -o Debug::NoLocking=1 --no-install-recommends --no-remove install needrestart 2>/dev/null); then result=0; else result=$?; fi
    if [ "${#raw}" -gt 65536 ]; then state=TOO_LARGE
    elif normalized=$(printf '%s\n' "$raw" | psp_actions); then
        if [ "${#normalized}" -gt 16000 ]; then state=TOO_LARGE
        elif [ -n "$normalized" ]; then actions=$(printf '%s\n' "$normalized" | base64 -w 0); fi
    else state=INVALID; fi
    printf 'BEGIN_PAYTM_SCANNER_PLAN_%s\nVERSION=1\nRUN_ID=%s\n' "$run" "$run"
    printf 'REVIEW_B64=%s\nSIMULATION_EXIT=%s\nACTIONS_STATE=%s\nACTIONS_B64=%s\n' "$(printf '%s\n' "$review" | base64 -w 0)" "$result" "$state" "$actions"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_SCANNER_PLAN_%s\n' "$run"
    printf '[VPS 100%%] Preview only. Do not install or restart from this report.\n'
)
