#!/usr/bin/env bash
# Definitions only. Observation, never install/restart/reboot/reset-failed.
pr_nr_sanitize() {
    # Never expose session/user/container descriptions or unrecognized free text.
    awk '
      /^NEEDRESTART-(SESS|CONT):/ {sub(/:.*/,": REDACTED"); print; next}
      /^NEEDRESTART-(VER|KCUR|KEXP|KSTA|UCSTA|UCCUR|UCEXP|SVC): [A-Za-z0-9_.+@:~=-]+$/ {print; next}
      NF {print "UNRECOGNIZED_OUTPUT"}
    '
}
pr_units_sanitize() {
    awk 'NF {if($1 ~ /^[A-Za-z0-9_.@:-]+[.]service$/)print $1;else print "UNRECOGNIZED_UNIT"}'
}
pr_targets() {
    local rows expected; local -a packages
    mapfile -t packages < <(mu_expected | cut -d'|' -f1)
    [ "${#packages[@]}" = 70 ] || return 1
    rows=$(timeout 30s dpkg-query -W '-f=${Package}|${db:Status-Abbrev}|${Version}\n' "${packages[@]}") || return 1
    rows=$(printf '%s\n' "$rows" | awk -F'|' 'NF!=3 || $2!="ii " {exit 2} {print $1 "|" $3}' | sort) || return 1
    expected=$(mu_expected | awk -F'|' '{print $1 "|" $3}' | sort) || return 1
    [ "$rows" = "$expected" ]
}
pr_main() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C NEEDRESTART_MODE=l
    local run="${1:-}" baseline raw tool nr_state=UNAVAILABLE nr_exit=NOT_RUN nr=NONE units=NONE unit_exit=UNKNOWN targets=NO marker=ABSENT
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || return 1
    printf '[VPS 10%%] Read-only health, installed targets and restart review.\n'
    raw=$(pm_main "$run") || { printf 'STOP: identity or baseline collection failed.\n'; return 1; }
    baseline=$(printf '%s\n' "$raw" | awk '/^BEGIN_PAYTM_MAINTENANCE_/ {capture=1} capture {print} /^END_PAYTM_MAINTENANCE_/ {capture=0}')
    [ "${#baseline}" -le 40000 ] || return 1
    pr_targets && targets=YES
    [ ! -e /var/run/reboot-required ] || marker=PRESENT
    printf '[VPS 50%%] Checking failed service names and list-only restart scanner; up to 90 seconds for scanner.\n'
    if raw=$(timeout 15s systemctl --failed --type=service --no-legend --plain --no-pager 2>/dev/null); then
        unit_exit=0; units=$(printf '%s\n' "$raw" | pr_units_sanitize | base64 -w 0); [ -n "$units" ] || units=NONE
    else unit_exit=$?; fi
    tool=$(command -v needrestart || true)
    if [[ "$tool" = /usr/sbin/needrestart || "$tool" = /usr/bin/needrestart ]]; then
        nr_state=PRESENT
        if raw=$(timeout --kill-after=5s 90s "$tool" -b -r l 2>/dev/null); then nr_exit=0; else nr_exit=$?; fi
        if [ "${#raw}" -le 32768 ]; then nr=$(printf '%s\n' "$raw" | pr_nr_sanitize | base64 -w 0); [ -n "$nr" ] || nr=NONE
        else nr=TOO_LARGE; fi
    fi
    [ "${#units}" -le 16384 ] || units=TOO_LARGE
    printf 'BEGIN_PAYTM_RESTART_%s\nVERSION=1\nRUN_ID=%s\n' "$run" "$run"
    printf 'BASELINE_B64=%s\nTARGETS_VERIFIED=%s\nREBOOT_MARKER=%s\n' "$(printf '%s\n' "$baseline" | base64 -w 0)" "$targets" "$marker"
    printf 'FAILED_UNITS_EXIT=%s\nFAILED_UNITS_B64=%s\nNEEDRESTART_STATE=%s\nNEEDRESTART_EXIT=%s\nNEEDRESTART_B64=%s\n' "$unit_exit" "$units" "$nr_state" "$nr_exit" "$nr"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_RESTART_%s\n' "$run"
    printf '[VPS 100%%] Observation complete. No restart, install, reboot or activation.\n'
)
