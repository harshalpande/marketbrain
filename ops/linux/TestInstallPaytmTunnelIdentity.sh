#!/usr/bin/env bash
# Offline guard tests only; no accounts, real SSH daemon or system config changes.
set -euo pipefail
source "$(dirname "$0")/InstallPaytmTunnelIdentity.sh"
checks=0
pass() { checks=$((checks+1)); }
reject() { if "$@" >/dev/null 2>&1; then printf 'Unexpected success: %s\n' "$*"; exit 1; fi; pass; }
fixture=$(mktemp -d)
trap 'rm -f -- "$fixture/config" "$fixture/key"; rmdir -- "$fixture"' EXIT

policy=$(tg_expected)
printf 'Testing exact gateway policy and missing/weakened controls...\n'
tg_policy "$policy"; pass
while IFS= read -r field; do
    reject tg_policy "${policy/$field/}"
    reject tg_policy "${policy/$field/$field-invalid}"
done <<< "$policy"
for field in allowusers denyusers allowgroups denygroups; do reject tg_policy "$policy"$'\n'"$field root"; done

printf '# standard\nInclude /etc/ssh/sshd_config.d/*.conf\nUsePAM yes\n' > "$fixture/config"
tg_config_text "$fixture/config" yes; pass
reject tg_config_text "$fixture/config" no
for line in 'Match User another' '  mAtCh all' 'Include /custom/path' 'Include /etc/ssh/sshd_config.d/*.conf /another' 'Include relative.conf'; do
    printf '%s\n' "$line" > "$fixture/config"
    reject tg_config_text "$fixture/config" yes
done
printf '# Match User is only a comment\n#Include /custom\nPasswordAuthentication yes\n' > "$fixture/config"
tg_config_text "$fixture/config" no; pass
for line in 'SSHD_OPTS=' 'SSHD_OPTS=""' "SSHD_OPTS=''" '#SSHD_OPTS=-f /custom'; do
    printf '%s\n' "$line" > "$fixture/config"
    tg_defaults "$fixture/config"; pass
done
for line in 'SSHD_OPTS=-f /custom' 'SSHD_OPTS="-o PasswordAuthentication=yes"' 'export SSHD_OPTS=' 'OTHER=value'; do
    printf '%s\n' "$line" > "$fixture/config"
    reject tg_defaults "$fixture/config"
done

timeout() { return 2; }
tg_absent passwd fixture; pass
timeout() { return 0; }; reject tg_absent passwd fixture
timeout() { return 124; }; reject tg_absent passwd fixture
timeout() { return 1; }; reject tg_absent passwd fixture
unset -f timeout
reject tg_new "$fixture/config"
tg_new "$fixture/absent"; pass
stat() { if [ "$2" = %u ]; then printf '0\n'; else printf '644\n'; fi; }
tg_owned "$fixture/config"; pass
stat() { if [ "$2" = %u ]; then printf '1000\n'; else printf '644\n'; fi; }; reject tg_owned "$fixture/config"
stat() { if [ "$2" = %u ]; then printf '0\n'; else printf '664\n'; fi; }; reject tg_owned "$fixture/config"
stat() { if [ "$2" = %u ]; then printf '0\n'; else printf '666\n'; fi; }; reject tg_owned "$fixture/config"
unset -f stat
tg_same_hash "$fixture/config" "$(tg_hash "$fixture/config")"; pass
reject tg_same_hash "$fixture/config" wrong

systemctl() { printf 'inactive\n'; }; ss() { return 0; }
tg_proxy_stopped; pass
systemctl() { return 1; }; reject tg_proxy_stopped
systemctl() { printf 'active\n'; }; reject tg_proxy_stopped
systemctl() { printf 'inactive\n'; }; ss() { return 1; }; reject tg_proxy_stopped
ss() { printf 'LISTEN\n'; }; reject tg_proxy_stopped
unset -f systemctl ss

TG_ROOT_POLICY=root-policy TG_ADMIN_POLICY=admin-policy
tg_effective() { case "$2" in root) printf 'root-policy\n';; marketbrain-admin) printf 'admin-policy\n';; *) tg_expected;; esac; }
tg_compare candidate; pass
TG_ROOT_POLICY=drift; reject tg_compare candidate
TG_ROOT_POLICY=root-policy TG_ADMIN_POLICY=drift; reject tg_compare candidate
TG_ADMIN_POLICY=admin-policy
tg_effective() { return 1; }; reject tg_compare candidate

tg_key > "$fixture/key"
fingerprint=$(ssh-keygen -l -E sha256 -f "$fixture/key" | awk '{print $2}')
[ "$fingerprint" = SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI ]; pass
[ "$fingerprint" != SHA256:xIUVGfImY7tqFFh+VCm/0CmcdVBYyl0fZyFL7bKIxrs ]; pass
key=$(tg_key)
[[ "$key" == 'restrict,port-forwarding,permitopen="127.0.0.1:18888",command="/usr/sbin/nologin" ssh-ed25519 '* ]]; pass
block=$(tg_block)
[ "$(grep -c '^Match ' <<< "$block")" = 1 ]; pass
grep -Fxq 'Match User marketbrain-gateway' <<< "$block"; pass
while IFS= read -r field; do
    case "$field" in 'strictmodes yes'|'usepam yes'|'usedns no'|'disableforwarding no'|'chrootdirectory none') continue;; esac
    grep -Fxiq "    $field" <<< "$block"; pass
done <<< "$policy"

# Recovery mocked without any real /etc writes. Unknown edits must never be replaced.
TG_WORK="$fixture" TG_OLD_HASH=old TG_NEW_HASH=new TG_INCLUDES=includes
tg_same_hash() { [ "$2" = old ]; }
tg_rollback "$fixture/config" "$fixture/absent" >/dev/null; pass
tg_same_hash() { return 1; }
reject tg_rollback "$fixture/config" "$fixture/absent"
tg_same_hash() { [ "$2" = new ]; }
tg_manifest() { printf 'drift\n'; }
reject tg_rollback "$fixture/config" "$fixture/absent"
TG_INCLUDES=''; tg_manifest() { return 1; }; reject tg_rollback "$fixture/config" "$fixture/absent"
TG_INCLUDES=includes
tg_manifest() { printf 'includes\n'; }
timeout() { return 1; }
reject tg_rollback "$fixture/config" "$fixture/absent"
timeout() { return 0; }
cp() { return 1; }; reject tg_rollback "$fixture/config" "$fixture/absent"
cp() { return 0; }; mv() { return 1; }; reject tg_rollback "$fixture/config" "$fixture/absent"
mv() { return 0; }; timeout() { [[ "$*" != *'systemctl reload'* ]]; }; reject tg_rollback "$fixture/config" "$fixture/absent"
timeout() { return 0; }; tg_rollback "$fixture/config" "$fixture/absent" >/dev/null; pass
unset -f cp mv timeout

uname() { printf 'NOT_LINUX\n'; }; reject tg_main
uname() { printf 'Linux\n'; }; id() { printf '1000\n'; }; reject tg_main
printf 'PASS: %s offline assertions. No real Debian SSH reload, key login or tunnel traffic tested.\n' "$checks"
