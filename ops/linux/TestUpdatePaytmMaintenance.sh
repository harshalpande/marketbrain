#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmOperations.sh"
source "$(dirname "$0")/PaytmReviewedPackages.sh"
source "$(dirname "$0")/UpdatePaytmMaintenance.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2"; exit 1; }; count=$((count+1)); }
reject() { if "$@" >/dev/null 2>&1; then printf 'FAIL: expected rejection\n'; exit 1; else count=$((count+1)); fi; }
plan=$(mu_expected | awk -F'|' '{print "Inst " $1 " [" $2 "] (" $3 " Debian [amd64])"}')
mu_plan "$plan"; count=$((count+1))
reject mu_plan "$plan"$'\nRemv unsafe [1]'
reject mu_plan "$(printf '%s\n' "$plan" | head -69)"
reject mu_plan "$plan"$'\nInst extra (1 Debian [amd64])'
reject mu_plan "$plan"$'\nInst libc6 [1] (2 Debian [amd64])'
reject mu_plan "${plan/libc6/unknown}"
reject mu_plan "${plan/2026e-0+deb13u1/2026c-0+deb13u1}"
reject mu_plan "${plan/2026e-0+deb13u1/2026f-0+deb13u1}"
fixture=$(mktemp -d)
prior_fixture="$fixture/prior-evidence"; mkdir "$prior_fixture"
printf '%s\n' 7fb461f8bff74ee0bb15a5afed8c49bc >"$prior_fixture/run-id"
mu_prior_receipt >"$prior_fixture/receipt.txt"
pb_parent() { [[ "${prior_mode:-}" != parent ]]; }
stat() {
    if [ "$2" = %s ]; then if [ "${prior_mode:-}" = large ]; then printf 3000; else printf 500; fi
    elif [ "${prior_mode:-}" = permissions ]; then printf 1000:1000:777
    elif [ "$3" = "$prior_fixture" ]; then printf 0:0:700
    else printf 0:0:600; fi
}
mu_prior_files "$prior_fixture"; count=$((count+1))
for prior_mode in parent large permissions; do reject mu_prior_files "$prior_fixture"; done
prior_mode=clean
original_receipt=$(mu_prior_receipt)
for changed in "${original_receipt/INSTALL_ATTEMPTED=no/INSTALL_ATTEMPTED=yes}" "${original_receipt/PHASE=SIMULATE/PHASE=INSTALL}" "${original_receipt/EXIT_CODE=1/EXIT_CODE=0}" "${original_receipt/UPGRADE_PLAN_CHANGED/DOWNLOAD}"; do
    printf '%s\n' "$changed" >"$prior_fixture/receipt.txt"; reject mu_prior_files "$prior_fixture"
done
printf '%s\n' "$original_receipt" >"$prior_fixture/receipt.txt"
printf 'wrong\n' >"$prior_fixture/run-id"; reject mu_prior_files "$prior_fixture"
unset -f stat
failed_state=$'ActiveState=failed\nLoadState=loaded\nMainPID=0\nSubState=failed'
mu_prior_state "$failed_state"; count=$((count+1))
mu_prior_state $'LoadState=not-found\nMainPID=0\nActiveState=inactive\nSubState=dead'; count=$((count+1))
for state in "${failed_state/MainPID=0/MainPID=123}" "${failed_state/ActiveState=failed/ActiveState=active}" "${failed_state/SubState=failed/SubState=running}" "$failed_state"$'\nMainPID=0' '' UNKNOWN; do reject mu_prior_state "$state"; done
calls="$fixture/calls"
touch "$calls"
timeout() {
    printf 'timeout %s\n' "$*" >>"$calls"
    if [[ "$1" = --kill-after=* ]]; then shift; fi; shift; "$@"
}
dpkg() { [[ "$1" = --compare-versions && "$3" = lt ]] || return 99; return 0; }
dpkg-query() {
    if [[ "${version_mode:-before}" = before ]]; then mu_expected | awk -F'|' '{print $1 "|ii |" $2}'
    else mu_expected | awk -F'|' '{print $1 "|ii |" $3}'; fi
}
declare -a packages targets
mu_arguments; check "${#targets[@]}" 70
mu_versions before; count=$((count+1))
reject mu_versions after
version_mode=after; mu_versions after; count=$((count+1)); unset version_mode
# Archive hook validates full exact multiset and rejects missing/unknown archives.
declare -A archive_versions
while IFS='|' read -r name old new; do touch "$fixture/$name.deb"; archive_versions[$name]="$new"; done < <(mu_expected)
dpkg-deb() {
    local name=${2##*/}; name=${name%.deb}
    if [ "$3" = Package ]; then printf '%s\n' "$name"
    else printf '%s\n' "${archive_versions[$name]:-UNKNOWN}"; fi
}
archives=$(mu_expected | while IFS='|' read -r name old new; do printf '%s/%s.deb\n' "$fixture" "$name"; done)
printf '%s\n' "$archives" | mu_archive_hook; count=$((count+1))
if printf '%s\n' "$archives" | head -69 | mu_archive_hook >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
touch "$fixture/extra.deb"
if printf '%s\n%s\n' "$archives" "$fixture/extra.deb" | mu_archive_hook >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
# Actual guard with command observations mocked; no server or privileged commands.
id() { printf 0; }
uname() { printf Linux; }
po_hash() { if [ "${guard_mode:-}" = hash ]; then printf MISMATCH; else printf MATCH; fi; }
po_value() {
    case "$*" in
        ssh-keygen*) if [ "${guard_mode:-}" = identity ]; then printf WRONG; else printf '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI host (RSA)'; fi;;
        *ActiveState*) if [ "${guard_mode:-}" = active ]; then printf active; else printf inactive; fi;;
        *FragmentPath*) printf /etc/systemd/system/marketbrain-paytm-gateway.service;;
        *NeedDaemonReload*) if [ "${guard_mode:-}" = reload ]; then printf yes; else printf no; fi;;
        *) return 99;;
    esac
}
timeout() {
    case "$*" in
        *DropInPaths*) if [ "${guard_mode:-}" = dropin ]; then printf UNREVIEWED; fi;;
        *' ss '*) if [ "${guard_mode:-}" = listener ]; then printf LISTEN; fi;;
        *sshd*) [[ "${guard_mode:-}" != ssh ]];;
        *'dpkg --audit'*) if [ "${guard_mode:-}" = audit ]; then printf BROKEN; fi;;
        *showhold*) if [ "${guard_mode:-}" = held ]; then printf HELD; fi;;
        *) return 99;;
    esac
}
guard_mode=clean; mu_guard; count=$((count+1))
for guard_mode in identity hash active reload dropin listener ssh audit held; do reject mu_guard; done
unset -f id uname
source "$(dirname "$0")/InspectPaytmOperations.sh"
timeout() {
    printf 'timeout %s\n' "$*" >>"$calls"
    if [[ "$1" = --kill-after=* ]]; then shift; fi; shift; "$@"
}
# Transaction fixtures: all system/package commands mocked, files only under mktemp.
mu_guard() { [[ "${mode:-}" != guard ]]; }
mu_prior() { [[ "${mode:-}" != prior ]]; }
po_hash() { if [[ "${mode:-}" = backup ]]; then printf MISMATCH; else printf MATCH; fi; }
tar() { [[ "${mode:-}" != compare ]]; }
timedatectl() { printf yes; }
mu_versions() { [[ "${mode:-}" != versions && !( "${mode:-}" = post && "$1" = after ) ]]; }
apt-get() {
    printf 'apt %s\n' "$*" >>"$calls"
    case " $* " in
        *' update '*) [[ "${mode:-}" != refresh ]];;
        *' -s '*)
            if [[ "${mode:-}" = simulation && "$*" == *Debug::NoLocking* ]]; then return 124; fi
            if [[ "${mode:-}" = exactsimulation && "$*" != *Debug::NoLocking* ]]; then return 100; fi
            if [[ "${mode:-}" = plan || ( "${mode:-}" = exactplan && "$*" != *Debug::NoLocking* ) ]]; then printf 'Remv unsafe [1]\n'; else printf '%s\n' "$plan"; fi;;
        *' --download-only '*) [[ "${mode:-}" != download ]];;
        *' --no-download '*) [[ "$*" == *'--only-upgrade --no-remove --no-install-recommends'* && "$*" == *'DPkg::Pre-Install-Pkgs::=/bin/bash '* && "$*" == *'--force-confold'* ]] || return 99; [[ "${mode:-}" != install ]];;
        *) return 99;;
    esac
}
for mode in clean guard prior backup compare versions refresh simulation exactsimulation plan exactplan download install post; do
    directory="$fixture/$mode"; mkdir "$directory"; : >"$calls"
    run=0123456789abcdef0123456789abcdef; phase=PRECHECK; attempted=no; post=no; reboot=UNKNOWN; failure_code=NONE; archive=fixture
    apt_options=(-o DPkg::Lock::Timeout=30)
    if out=$(trap 'mu_receipt $?' EXIT; mu_execute 2>/dev/null); then rc=0; else rc=$?; fi
    if [ "$mode" = clean ]; then check "$out" POSTCHECKS_PASSED=yes; check "$out" PHASE=COMPLETE; [ "$rc" = 0 ] || exit 1
    else check "$out" POSTCHECKS_PASSED=no; [ "$rc" != 0 ] || exit 1; [[ "$out" != *'FAILURE_CODE=NONE'* ]] || exit 1; count=$((count+1)); fi
    case "$mode" in clean|install|post) check "$out" INSTALL_ATTEMPTED=yes;; *) check "$out" INSTALL_ATTEMPTED=no;; esac
    case "$mode" in simulation) check "$out" FAILURE_CODE=UPGRADE_SIMULATION_FAILED;; exactsimulation) check "$out" FAILURE_CODE=EXACT_SIMULATION_FAILED;; plan) check "$out" FAILURE_CODE=UPGRADE_PLAN_CHANGED;; exactplan) check "$out" FAILURE_CODE=EXACT_PLAN_CHANGED;; esac
    # Installation may run once, never via timeout. No fallback/repair/reboot commands.
    [[ "$(grep -c '^apt .*--no-download' "$calls" || true)" -le 1 ]] || exit 1
    if grep -q '^timeout .*--no-download' "$calls"; then exit 1; else count=$((count+1)); fi
done
printf 'PASS: %s assertions including fourteen mocked transactions, retry guards and archive-hook boundaries. No VPS/real apt/systemd invoked. Fixtures: %s\n' "$count" "$fixture"
