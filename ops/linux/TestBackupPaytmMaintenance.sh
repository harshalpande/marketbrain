#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmOperations.sh"
source "$(dirname "$0")/BackupPaytmMaintenance.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2"; exit 1; }; count=$((count+1)); }
# Real GNU tar fixture on disposable local data, no VPS/system paths are changed.
# Windows Git Bash cannot enforce Linux RLIMIT_FSIZE; mock only that primitive.
ulimit() { [[ "$*" = '-f 1048576' ]] && return "${limit_exit:-0}"; }
fixture=$(mktemp -d)
mkdir "$fixture/source" "$fixture/private"
printf 'fixture content\n' >"$fixture/source/example"
umask 077
pb_archive "$fixture/source" "$fixture/private" example
check "$(tar -tf "$fixture/private/configuration.tar")" example
before=$(sha256sum "$fixture/private/configuration.tar")
if pb_archive "$fixture/source" "$fixture/private" example; then exit 1; else count=$((count+1)); fi
check "$(sha256sum "$fixture/private/configuration.tar")" "$before"
printf 'modified\n' >>"$fixture/source/example"
if tar --compare --file "$fixture/private/configuration.tar" --directory "$fixture/source" >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
# Failed create leaves private partial files and must not report success.
mkdir "$fixture/failed"
if pb_archive "$fixture/source" "$fixture/failed" missing >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
mkdir "$fixture/limit"
limit_exit=1
if pb_archive "$fixture/source" "$fixture/limit" example >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
[ ! -e "$fixture/limit/configuration.tar" ] || exit 1
unset limit_exit
# Mock system inspection below. Abort tests all stop before any real VPS writes.
timeout() { shift; if [[ "$1" = /usr/sbin/sshd ]]; then return 0; fi; "$@"; }
uname() { printf Linux; }
id() { printf '%s' "${uid:-0}"; }
export SUDO_USER=marketbrain-admin
ssh-keygen() { printf '3072 %s fixture (RSA)\n' "${pin:-SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI}"; }
po_hash() { printf '%s' "${hash:-MATCH}"; }
systemctl() { printf '%s' "${state:-inactive}"; }
ss() { if [[ "${listener:-}" = yes ]]; then printf occupied; fi; }
dpkg() { [[ "$*" = --audit ]] || return 99; if [[ "${audit:-}" = bad ]]; then printf PRIVATE_AUDIT_TEXT; fi; }
pb_parent() { return 1; }
run=0123456789abcdef0123456789abcdef
for scenario in user pin hash state listener audit parent; do
    unset uid pin hash state listener audit
    case "$scenario" in user) uid=1000;; pin) pin=WRONG;; hash) hash=MISMATCH;; state) state=active;; listener) listener=yes;; audit) audit=bad;; esac
    if out=$(pb_main "$run" 2>/dev/null); then exit 1; fi
    check "$out" DIRECTORY_CREATED=no
    check "$out" ARCHIVE_VERIFIED=no
    check "$out" "END_PAYTM_BACKUP_$run"
    [[ "$out" != *PRIVATE_AUDIT_TEXT* ]] || exit 1
done
if pb_main invalid >/dev/null 2>&1; then exit 1; else count=$((count+1)); fi
printf 'PASS: %s assertions (native GNU tar fixture plus mocked pre-write guards). Retained fixtures: %s\n' "$count" "$fixture"
