#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/InspectPaytmScannerPlan.sh"
source "$(dirname "$0")/InstallPaytmScanner.sh"
count=0
check() { [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s\n' "$2";exit 1; };count=$((count+1)); }
reject() { if "$@" >/dev/null 2>&1;then printf 'FAIL: expected rejection\n';exit 1;else count=$((count+1));fi; }
declare -a packages targets
si_arguments;check "${#targets[@]}" 6
plan=$(si_expected | awk -F'|' '{print "Inst " $1 " (" $2 " Debian [" $3 "])"; print "Conf " $1 " (" $2 " Debian [" $3 "])"}')
si_plan "$plan";count=$((count+1))
si_source_text_safe $'Types: deb\nURIs: http://deb.debian.org/debian\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg';count=$((count+1))
si_source_text_safe '# Trusted: yes';count=$((count+1))
for bad in 'Trusted: yes' 'Trusted: true' 'deb [trusted=yes] http://fixture stable main' 'deb [trusted="yes"] http://fixture stable main' 'Allow-Insecure: yes' 'Check-Valid-Until: no' 'deb [check-date=false] http://fixture stable main';do reject si_source_text_safe "$bad";done
reject si_source_text_safe "Trusted: yes"$'\n'"$(printf '%0100000d' 0)"
for bad in "${plan/3.11-1/3.12-1}" "$plan"$'\nRemv extra [1]' "$plan"$'\nConf extra (1 Debian)' "$plan"$'\nInst extra (1 Debian)' "$plan"$'\nInst needrestart (3.11-1 Debian)' "${plan/Inst needrestart (/Inst needrestart [3.10-1] (}"; do reject si_plan "$bad";done
uris=$(si_expected | awk -F'|' '{print "\047https://deb.debian.org/debian/pool/main/n/" $1 "_" $2 "_" $3 ".deb\047 " $1 ".deb 100 SHA256:0123456789abcdef"}')
si_origins "$uris";count=$((count+1))
si_origins "${uris/https:/http:}";count=$((count+1))
for bad in "${uris/deb.debian.org/evil.test}" "${uris/deb.debian.org/deb.debian.org.evil.test}" "${uris/deb.debian.org/user:password@deb.debian.org}" "${uris/https:/file:}" "${uris/100 SHA256/999999999 SHA256}" "$uris"$'\n'"${uris%%$'\n'*}" "$(printf '%s\n' "$uris"|head -5)" "${uris/SHA256:0123456789abcdef/INVALID}";do reject si_origins "$bad";done
timeout() { if [[ "$1" = --kill-after=* ]];then shift;fi;shift;"$@"; }
dpkg-query() { if [[ "$*" == *Architecture* ]];then si_expected | awk -F'|' '{print $1 "|ii |" $2 "|" $3}';else return "${query_rc:-1}";fi; }
si_absent;count=$((count+1))
query_rc=2;reject si_absent;unset query_rc
si_versions;count=$((count+1))
dpkg-query() { si_expected | awk -F'|' '{print $1 "|iU |" $2 "|" $3}'; }
reject si_versions
fixture=$(mktemp -d);mkdir "$fixture/archives"
declare -A versions architectures
while IFS='|' read -r name version architecture;do touch "$fixture/archives/$name.deb";versions[$name]=$version;architectures[$name]=$architecture;done < <(si_expected)
dpkg-deb() { local name=${2##*/};name=${name%.deb};case "$3" in Package)printf '%s' "$name";;Version)printf '%s' "${versions[$name]:-UNKNOWN}";;Architecture)printf '%s' "${architectures[$name]:-UNKNOWN}";;*)return 99;;esac; }
archives=$(si_expected | while IFS='|' read -r name version architecture;do printf '%s/archives/%s.deb\n' "$fixture" "$name";done)
printf '%s\n' "$archives"|si_archive_rows "$fixture";count=$((count+1))
if printf '%s\n' "$archives"|head -5|si_archive_rows "$fixture";then exit 1;else count=$((count+1));fi
if printf '%s\n%s\n' "$archives" "${archives%%$'\n'*}"|si_archive_rows "$fixture";then exit 1;else count=$((count+1));fi
architectures[needrestart]=arm64
if printf '%s\n' "$archives"|si_archive_rows "$fixture";then exit 1;else count=$((count+1));fi
architectures[needrestart]=all;versions[needrestart]=3.12-1
if printf '%s\n' "$archives"|si_archive_rows "$fixture";then exit 1;else count=$((count+1));fi
calls="$fixture/calls"
mu_guard() { [[ "${mode:-}" != guard ]]; }
pr_targets() { [[ "${mode:-}" != targets ]]; }
si_absent() { [[ "${mode:-}" != installed ]]; }
si_backup() { [[ "${mode:-}" != backup ]]; }
si_sources() { [[ "${mode:-}" != trust ]]; }
si_versions() { [[ "${mode:-}" != post ]]; }
si_list_config() { [[ "${mode:-}" != config ]]; }
po_value() { if [[ "${mode:-}" = time ]];then printf no;else printf yes;fi; }
dpkg() { [[ "$*" = --print-architecture ]] || return 99;printf amd64; }
sha256sum() { [[ "$*" == '--check --status '* ]] || return 99;[[ "${mode:-}" != drift ]]; }
apt-get() {
    printf 'apt %s\n' "$*" >>"$calls"
    case " $* " in
      *' update '*) [[ "${mode:-}" != refresh ]];;
      *' -s '*)
        [[ "${mode:-}" != simulation ]] || return 100
        if [[ "${mode:-}" = candidate || ( "${mode:-}" = exact && "$*" = *needrestart=3.11-1* ) ]];then printf 'Inst extra (1 Debian)\n';else printf '%s\n' "$plan";fi;;
      *' --print-uris '*) if [[ "${mode:-}" = origin ]];then printf '%s\n' "${uris/deb.debian.org/evil.test}";else printf '%s\n' "$uris";fi;;
      *' --download-only '*) [[ "${mode:-}" != download ]];;
      *' --no-download '*)
        [[ "$*" == *'--no-remove --no-install-recommends'* && "$*" == *'DPkg::Pre-Install-Pkgs::=/bin/bash '* ]] || return 99
        [[ "$NEEDRESTART_SUSPEND" = 1 && "$NEEDRESTART_MODE" = l ]] || return 99
        [[ "${mode:-}" != install ]];;
      *) return 99;;
    esac
}
# Mock executable availability without creating anything under /usr/sbin.
si_scanner_available() { [[ "${mode:-}" != scanner ]]; }
timeout() {
    printf 'timeout %s\n' "$*" >>"$calls"
    if [[ "$1" = --kill-after=* ]];then shift;fi;shift
    if [[ "$1" = /bin/bash && "$*" == *'worker.sh scan' ]];then
        [[ "${mode:-}" != scan ]] || return 124
        if [[ "${mode:-}" = receipt ]];then printf INCOMPLETE;else printf 'BEGIN_PAYTM_RESTART_%s\nCAPTURE_COMPLETE=yes\nEND_PAYTM_RESTART_%s\n' "$run" "$run";fi
    else "$@";fi
}
export NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l
for mode in clean guard targets installed time trust backup refresh simulation candidate exact origin download drift install post config scanner scan receipt;do
    directory="$fixture/$mode";mkdir "$directory";: >"$calls"
    run=0123456789abcdef0123456789abcdef;phase=PRECHECK;attempted=no;post=no;origins=no;configured=no;review=NONE;failure_code=NONE;apt_options=()
    if out=$(trap 'si_receipt $?' EXIT;si_execute 2>/dev/null);then rc=0;else rc=$?;fi
    if [[ "$mode" = clean ]];then check "$out" PHASE=COMPLETE;check "$out" POSTCHECKS_PASSED=yes;[[ "$rc" = 0 ]] || exit 1
    else [[ "$rc" != 0 && "$out" != *FAILURE_CODE=NONE* ]] || exit 1;count=$((count+1));fi
    case "$mode" in clean|install|post|config|scanner|scan|receipt)check "$out" INSTALL_ATTEMPTED=yes;;*)check "$out" INSTALL_ATTEMPTED=no;;esac
    [[ "$(grep -c '^apt .*--no-download' "$calls" || true)" -le 1 ]] || exit 1;count=$((count+1))
    if grep -q '^timeout .*--no-download' "$calls";then exit 1;else count=$((count+1));fi
done
mode=clean
pb_parent() { return 0; }
stat() { printf '0:0:700'; }
mkdir() { return 1; } # Existing/failed stage must stop before any write or service launch.
export SUDO_USER=marketbrain-admin
reject si_launch bad
reject si_launch "$run"
SUDO_USER=wrong;reject si_launch "$run"
reject si_poll bad
printf 'PASS: %s assertions including twenty mocked install transactions. No real APT/systemd/VPS calls. Fixtures: %s\n' "$count" "$fixture"
