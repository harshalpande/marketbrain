#!/usr/bin/env bash
# Definitions only. Observe is read-only. Reboot requires a separate, boot-bound command.
rb_host() {
    [ "${SUDO_USER:-}" = marketbrain-admin ] && mu_guard
}
rb_boot() { cat /proc/sys/kernel/random/boot_id; }
rb_idle() {
    local rows code=0
    rows=$(timeout 10s ps -eo comm=) || return 1
    # Consume all output, including under pipefail. This is an observation, not a package lock.
    printf '%s\n' "$rows" | grep -Ex '[[:space:]]*(apt|apt-get|dpkg|unattended-upgr|unattended-upgrade|unattended-upgrades)[[:space:]]*' >/dev/null || code=$?
    [ "$code" = 1 ] || return 1
    rows=$(timeout 10s systemctl list-jobs --no-legend --no-pager) && [ -z "$rows" ] || return 1
    [ ! -e /run/systemd/shutdown/scheduled ] && [ ! -L /run/systemd/shutdown/scheduled ]
}
rb_gateway_disabled() {
    local value code=0
    value=$(timeout 10s systemctl is-enabled marketbrain-paytm-gateway.service 2>/dev/null) || code=$?
    [ "$code" = 1 ] && [ "$value" = disabled ]
}
rb_core_active() {
    local service value
    for service in cron.service dbus.service ssh.service systemd-logind.service systemd-timesyncd.service systemd-udevd.service; do
        value=$(timeout 10s systemctl is-active "$service") && [ "$value" = active ] || return 1
    done
}
rb_backup() {
    local path directory=/var/backups/marketbrain-maintenance/scanner-install-20261023
    for path in /var /var/backups /var/backups/marketbrain-maintenance "$directory"; do pb_parent "$path" || return 1; done
    [ "$(stat -c '%u:%g:%a' "$directory")" = 0:0:700 ] || return 1
    for path in "$directory/run-id" "$directory/receipt.txt" "$directory/configuration.tar"; do
        [ -f "$path" ] && [ ! -L "$path" ] && [ "$(stat -c '%u:%g:%a' "$path")" = 0:0:600 ] || return 1
    done
    [ "$(stat -c %s "$directory/run-id")" -le 64 ] && [ "$(cat "$directory/run-id")" = 7e54c5029aca42e3a96c8e0195311723 ] || return 1
    [ "$(stat -c %s "$directory/receipt.txt")" -le 60000 ] || return 1
    for path in PHASE=COMPLETE EXIT_CODE=0 POSTCHECKS_PASSED=yes FAILURE_CODE=NONE CAPTURE_COMPLETE=yes; do
        [ "$(grep -Fxc "$path" "$directory/receipt.txt")" = 1 ] || return 1
    done
    [ "$(stat -c %s "$directory/configuration.tar")" -gt 0 ] && [ "$(stat -c %s "$directory/configuration.tar")" -le 1073741824 ] || return 1
    # Readability only; not a restore test or comparison against post-install files.
    timeout --kill-after=5s 30s tar -tf "$directory/configuration.tar" >/dev/null 2>&1
}
rb_virtualization() {
    local kind="$1" value code=0
    value=$(timeout 10s systemd-detect-virt "--$kind" 2>/dev/null) || code=$?
    if [ "$code" = 1 ] && [ "$value" = none ]; then printf none
    elif [ "$code" = 0 ] && [[ "$value" =~ ^[a-z0-9-]{1,30}$ ]]; then printf '%s' "$value"
    else printf UNKNOWN; fi
}
rb_observe() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local run="${1:-}" phase="${2:-}" raw review boot epoch scanner=NO backup=NO idle=NO disabled=NO core=NO
    [[ "$run" =~ ^[a-f0-9]{32}$ && "$phase" =~ ^(BEFORE|AFTER)$ ]] || return 1
    rb_host || { printf 'REBOOT_STOP=HOST_OR_BASELINE_GUARD\n'; return 1; }
    boot=$(rb_boot); epoch=$(date -u +%s)
    [[ "$boot" =~ ^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$ && "$epoch" =~ ^[0-9]{10}$ ]] || return 1
    printf '[VPS] %s: collecting boot identity, backup readability, idle state and fresh restart screen.\n' "$phase"
    si_arguments && si_versions && scanner=YES
    rb_backup && backup=YES
    rb_idle && idle=YES
    rb_gateway_disabled && disabled=YES
    rb_core_active && core=YES
    raw=$(pr_main "$run") || { printf 'REBOOT_STOP=SCAN_COLLECTION\n'; return 1; }
    review=$(printf '%s\n' "$raw" | awk '/^BEGIN_PAYTM_RESTART_/ {capture=1} capture {print} /^END_PAYTM_RESTART_/ {capture=0}')
    [ "${#review}" -le 40000 ] && [ "$(rb_boot)" = "$boot" ] || return 1
    printf 'BEGIN_PAYTM_REBOOT_%s\nVERSION=1\nRUN_ID=%s\nPHASE=%s\n' "$run" "$run" "$phase"
    printf 'BOOT_ID=%s\nUTC_EPOCH=%s\n' "$boot" "$epoch"
    printf 'VM=%s\nCONTAINER=%s\n' "$(rb_virtualization vm)" "$(rb_virtualization container)"
    printf 'SCANNER_PACKAGES=%s\nBACKUP_READABLE=%s\nJOBS_IDLE=%s\nGATEWAY_DISABLED=%s\n' "$scanner" "$backup" "$idle" "$disabled"
    printf 'CORE_SERVICES_ACTIVE=%s\n' "$core"
    printf 'REVIEW_B64=%s\nCAPTURE_COMPLETE=yes\nEND_PAYTM_REBOOT_%s\n' "$(printf '%s\n' "$review" | base64 -w 0)" "$run"
)
rb_reboot() (
    # No force, no delayed job, no recurring task. Same boot + 20-minute VPS-time lease.
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local expected="${1:-}" captured="${2:-}" now
    [[ "$expected" =~ ^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$ && "$captured" =~ ^[0-9]{10}$ ]] || return 1
    now=$(date -u +%s)
    [[ "$now" =~ ^[0-9]{10}$ ]] && [ "$now" -ge "$captured" ] && [ "$((now-captured))" -le 1200 ] || { printf 'REBOOT_STOP=EXPIRED_OR_CLOCK_CHANGED\n'; return 1; }
    [ "$(rb_boot)" = "$expected" ] || { printf 'REBOOT_STOP=BOOT_ALREADY_CHANGED_DO_NOT_REPEAT\n'; return 1; }
    rb_host && rb_gateway_disabled && rb_idle && rb_backup && rb_core_active && pr_targets && si_arguments && si_versions || {
        printf 'REBOOT_STOP=FRESH_GUARD_FAILED_NO_REBOOT\n'; return 1;
    }
    [ "$(po_value timedatectl show -p NTPSynchronized --value)" = yes ] || return 1
    now=$(date -u +%s)
    [[ "$now" =~ ^[0-9]{10}$ ]] && [ "$now" -ge "$captured" ] && [ "$((now-captured))" -le 1200 ] && [ "$(rb_boot)" = "$expected" ] && rb_idle || return 1
    # Deliberate user paste after local confirmation is the execution boundary.
    printf 'REBOOT_REQUESTED_EXPECT_PUTTY_DISCONNECT\n'
    systemctl reboot
)
