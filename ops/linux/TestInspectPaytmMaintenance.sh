#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmOperations.sh"
source "$(dirname "$0")/InspectPaytmMaintenance.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2"; exit 1; }; count=$((count+1)); }
timeout() { if [[ "$1" == --kill-after=* ]]; then shift; fi; shift; if [[ "$1" = /usr/sbin/sshd ]]; then return "${ssh_exit:-0}"; fi; "$@"; }
uname() { printf Linux; }
id() { printf '%s' "${uid:-0}"; }
export SUDO_USER=marketbrain-admin
ssh-keygen() { printf '3072 %s fixture (RSA)\n' "${pin:-SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI}"; }
po_hash() { printf '%s' "${hash:-MATCH}"; }
systemctl() { case "$*" in *ActiveState*) printf '%s' "${state:-inactive}";; *DropInPaths*) :;; *NeedDaemonReload*) printf no;; *) return 98;; esac; }
ss() { return "${ss_exit:-0}"; }
dpkg() { [[ "$*" = --audit ]] || return 99; if [[ "${audit:-}" = findings ]]; then printf PRIVATE_AUDIT_DETAILS; fi; return "${audit_exit:-0}"; }
apt-mark() { [[ "$*" = showhold ]] || return 99; if [[ "${hold:-}" = yes ]]; then printf 'fixture\n'; fi; }
df() { printf 'Filesystem Size Used Available Percent Mounted\n'; if [[ "$1" = -Pk ]]; then printf 'fixture 9999999 1 8000000 1%% /\n'; else printf 'fixture 999999 1 90000 1%% /\n'; fi; }
timedatectl() { printf yes; }
apt-get() {
    [[ "$*" = '-s -o Debug::NoLocking=1 upgrade' ]] || return 99
    [[ "${apt_exit:-0}" = 0 ]] || return "$apt_exit"
    printf 'Inst libc6 [2.41-1] (2.41-2 Debian [amd64])\n'
    if [[ "${remove:-}" = yes ]]; then printf 'Remv fixture [1]\n'; fi
}
run=0123456789abcdef0123456789abcdef
out=$(pm_main "$run")
for text in HOST_IDENTITY=MATCH PROXY_CONFIG=MATCH ALLOWLIST=MATCH SERVICE_CONFIG=MATCH SERVICE_STATE=inactive DROPINS=NONE RELOAD_NEEDED=no LISTENER_COUNT=0 SSH_CONFIG_VALID=yes DPKG_AUDIT=CLEAN HOLD_COUNT=0 APT_FREE_KIB=8000000 APT_FREE_INODES=90000 NTP_SYNCHRONIZED=yes SIMULATION_EXIT=0 UPGRADE_COUNT=1 REMOVAL_COUNT=0 CAPTURE_COMPLETE=yes; do check "$out" "$text"; done
encoded=$(printf '%s\n' "$out" | sed -n 's/^CANDIDATES_B64=//p')
check "$(printf '%s' "$encoded" | base64 -d)" 'libc6|2.41-1|2.41-2'
audit=findings; out=$(pm_main "$run"); check "$out" DPKG_AUDIT=FINDINGS
[[ "$out" != *PRIVATE_AUDIT_DETAILS* ]] || exit 1; count=$((count+1)); unset audit
audit_exit=124; check "$(pm_main "$run")" DPKG_AUDIT=UNKNOWN; unset audit_exit
apt_exit=124; out=$(pm_main "$run"); check "$out" SIMULATION_EXIT=124; check "$out" UPGRADE_COUNT=UNKNOWN; unset apt_exit
hold=yes; check "$(pm_main "$run")" HOLD_COUNT=1; unset hold
remove=yes; check "$(pm_main "$run")" REMOVAL_COUNT=1; unset remove
ss_exit=1; check "$(pm_main "$run")" LISTENER_COUNT=UNKNOWN; unset ss_exit
ssh_exit=1; check "$(pm_main "$run")" SSH_CONFIG_VALID=no; unset ssh_exit
state=active; check "$(pm_main "$run")" SERVICE_STATE=active; unset state
hash=MISMATCH; check "$(pm_main "$run")" PROXY_CONFIG=MISMATCH; unset hash
for scenario in badrun wronguser wrongpin; do
    case "$scenario" in badrun) arg=bad;; wronguser) arg=$run; uid=1000;; wrongpin) arg=$run; pin=WRONG;; esac
    if pm_main "$arg" >/dev/null; then exit 1; else count=$((count+1)); fi
    unset uid pin
done
printf 'PASS: %s offline Bash assertions; no VPS commands executed.\n' "$count"
