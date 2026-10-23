#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
source PaytmRebootReview.sh
source StagePaytmLoopbackProxy.sh
source InspectPaytmOperations.sh
count=0
check() { [[ "$1" = *"$2"* ]] || { printf 'FAIL expected %s\n' "$2"; exit 1; }; count=$((count+1)); }
reject() { if "$@" >/dev/null 2>&1;then printf 'FAIL expected reject\n';exit 1;fi; count=$((count+1)); }
timeout() { if [[ "$1" = --kill-after=* ]];then shift;fi;shift;"$@"; }
ps() { [[ "${mode:-}" != psfail ]] || return 1; if [[ "${mode:-}" = busy ]];then printf 'dpkg\n';else printf 'bash\nsshd\n';fi; }
systemctl() {
    case "$*" in
        'list-jobs --no-legend --no-pager') [[ "${mode:-}" != jobsfail ]] || return 1;[[ "${mode:-}" != jobs ]] || printf '1 x.service start running\n';;
        'is-enabled marketbrain-paytm-gateway.service')
            case "${mode:-}" in enabled|enabled-runtime|alias|indirect|generated|transient) printf '%s\n' "$mode";; disabled|masked|linked|not-found) printf '%s\n' "$mode";return 1;; badcode) printf 'static\n';return 1;; timeout) return 124;; malformed) printf 'PRIVATE multiline\n';; *) printf 'static\n';; esac;;
        'show marketbrain-paytm-gateway.service -p WantedBy -p RequiredBy -p TriggeredBy')
            case "${mode:-}" in references) printf 'WantedBy=multi-user.target\nRequiredBy=\nTriggeredBy=\n';; referencesfail) return 124;; referencespartial) printf 'WantedBy=\n';; *) printf 'TriggeredBy=\nRequiredBy=\nWantedBy=\n';; esac;;
        'is-active '*) if [[ "${mode:-}" = core ]];then printf inactive;return 3;else printf active;fi;;
        reboot) printf 'MOCK_REBOOT_ONLY\n';;
        *) printf 'UNEXPECTED systemctl command\n' >&2; return 99;;
    esac
}
for mode in busy psfail jobs jobsfail;do reject rb_idle;done
mode=clean;rb_idle;count=$((count+1));rb_gateway_manual_only;count=$((count+1))
# Cross-module fixture: the ORIGINAL deployed unit is deliberately static.
unit=$(pg_unit)
[[ "$unit" != *'[Install]'* ]] || exit 1;count=$((count+1))
unit_hash=$(pg_unit | sha256sum);check "$unit_hash" ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2
check "$rb_gateway_state" static;check "$rb_gateway_exit" 0;check "$rb_gateway_references" NONE
if [ "$rb_gateway_exit" = 1 ] && [ "$rb_gateway_state" = disabled ]; then exit 1;fi;count=$((count+1))
for mode in enabled enabled-runtime alias indirect generated transient disabled masked linked not-found badcode timeout malformed references referencesfail referencespartial;do reject rb_gateway_manual_only;done
mode=clean;rb_core_active;count=$((count+1));mode=core;reject rb_core_active
systemd-detect-virt() { case "${mode:-}" in vm) printf kvm;; none) printf none;return 1;; malformed) printf 'PRIVATE description\n';; failed) return 124;; mismatch) printf none;; esac; }
for mode in vm none malformed failed;do
    value=$(rb_virtualization vm)
    case "$mode" in vm) check "$value" kvm;; none) check "$value" none;; *) check "$value" UNKNOWN;; esac
done
rb_host() { [[ "${mode:-}" != host ]]; }
# Keep the real gateway state function for all observation and reboot tests.
rb_idle() { [[ "${mode:-}" != busy ]]; }
rb_backup() { [[ "${mode:-}" != backup ]]; }
rb_core_active() { [[ "${mode:-}" != core ]]; }
pr_targets() { [[ "${mode:-}" != targets ]]; }
si_arguments() { return 0; }
si_versions() { [[ "${mode:-}" != scanner ]]; }
rb_boot() { if [[ "${mode:-}" = changed ]];then printf 22222222-2222-2222-2222-222222222222;else printf 11111111-1111-1111-1111-111111111111;fi; }
date() { case "${mode:-}" in expired) printf 1792751300;; reversed) printf 1792749999;; *) printf 1792750000;; esac; }
po_value() { if [[ "${mode:-}" = time ]];then printf no;else printf yes;fi; }
boot=11111111-1111-1111-1111-111111111111
for mode in host enabled busy backup core targets scanner changed time expired reversed;do reject rb_reboot "$boot" 1792750000;done
reject rb_reboot 'bad;reboot' 1792750000
reject rb_reboot "$boot" invalid
mode=clean;out=$(rb_reboot "$boot" 1792750000);check "$out" MOCK_REBOOT_ONLY;check "$out" REBOOT_REQUESTED_EXPECT_PUTTY_DISCONNECT
pr_main() { printf 'BEGIN_PAYTM_RESTART_%s\nVERSION=1\nEND_PAYTM_RESTART_%s\n' "$1" "$1"; }
rb_virtualization() { if [[ "$1" = vm ]];then printf kvm;else printf none;fi; }
run=0123456789abcdef0123456789abcdef
for mode in clean scanner backup busy enabled;do
    out=$(rb_observe "$run" BEFORE)
    check "$out" "BEGIN_PAYTM_REBOOT_$run"
    check "$out" 'CAPTURE_COMPLETE=yes'
    [[ "$out" != *MOCK_REBOOT* ]] || exit 1;count=$((count+1))
    check "$out" GATEWAY_QUERY_EXIT=0
    case "$mode" in scanner) check "$out" SCANNER_PACKAGES=NO;; backup) check "$out" BACKUP_READABLE=NO;; busy) check "$out" JOBS_IDLE=NO;; enabled) check "$out" GATEWAY_MANUAL_ONLY=NO;check "$out" GATEWAY_UNIT_STATE=enabled;; clean) check "$out" GATEWAY_MANUAL_ONLY=YES;check "$out" GATEWAY_UNIT_STATE=static;; esac
done
mode=host;reject rb_observe "$run" BEFORE
mode=clean;reject rb_observe bad BEFORE;reject rb_observe "$run" REBOOT
printf 'PASS: %s Bash assertions; mocked observations/reboot guards only. No VPS changes.\n' "$count"
