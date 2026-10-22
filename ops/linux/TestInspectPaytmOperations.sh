#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmOperations.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2"; exit 1; }; count=$((count+1)); }
timeout() { shift; "$@"; }
fixture_ok() { printf OK; }
fixture_bad() { printf PRIVATE_DO_NOT_INCLUDE; return 9; }
check "$(po_value fixture_ok)" OK
check "$(po_value fixture_bad)" UNKNOWN
check "$(po_field FIELD $'bad\nSECRET')" FIELD=UNKNOWN
check "$(po_field VERSION '1:10.0p1-7')" VERSION=1:10.0p1-7
sha256sum() { printf 'abc  /fixture\n'; }
check "$(po_hash /fixture abc)" MATCH
check "$(po_hash /fixture def)" MISMATCH
if po_main bad >/dev/null; then exit 1; else count=$((count+1)); fi
uname() { if [ "$1" = -s ]; then printf Linux; else printf fixture-kernel; fi; }
id() { printf 1000; }
export SUDO_USER=marketbrain-admin
if po_main 0123456789abcdef0123456789abcdef >/dev/null; then exit 1; else count=$((count+1)); fi
id() { printf 0; }
ssh-keygen() { printf '3072 WRONG fixture\n'; }
if po_main 0123456789abcdef0123456789abcdef >/dev/null; then exit 1; else count=$((count+1)); fi
ssh-keygen() { printf '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI fixture (RSA)\n'; }
po_hash() { printf MATCH; }
systemctl() {
    case "$*" in
        *ActiveState*) printf inactive;;
        *DropInPaths*|list-units*) :;;
        *NeedDaemonReload*) printf no;;
        *) return 97;;
    esac
}
ss() { :; }
curl() {
    [[ "$*" == '-q --ipv4 --noproxy * --proxy  --interface 130.250.191.137 --proto =https --connect-timeout 8 --max-time 15 --max-filesize 64 --fail --silent --show-error https://api.ipify.org/' ]] || return 90
    printf 130.250.191.137
}
timedatectl() { printf yes; }
dpkg-query() { printf 1.2.3; }
find() { printf '1790000000.0\n'; }
apt-get() { [[ "$*" == '-s -o Debug::NoLocking=1 upgrade' ]] || return 91; printf 'Inst fixture\nInst fixture2\n'; }
out=$(po_main 0123456789abcdef0123456789abcdef)
check "$out" HOST_IDENTITY=MATCH
check "$out" SERVICE_STATE=inactive
check "$out" WATCHDOG_UNIT_COUNT=0
check "$out" VPS_BOUND_PUBLIC_IPV4=130.250.191.137
check "$out" CACHED_UPGRADE_COUNT=2
check "$out" APT_OLDEST_RELEASE_EPOCH=1790000000
check "$out" CAPTURE_COMPLETE=yes
curl() { return 124; }
timedatectl() { return 1; }
apt-get() { return 1; }
out=$(po_main 0123456789abcdef0123456789abcdef)
check "$out" VPS_BOUND_PUBLIC_IPV4=UNKNOWN
check "$out" NTP_SYNCHRONIZED=UNKNOWN
check "$out" CACHED_UPGRADE_COUNT=UNKNOWN
check "$out" CAPTURE_COMPLETE=yes
printf 'PASS: %s offline assertions, no VPS or external calls.\n' "$count"
