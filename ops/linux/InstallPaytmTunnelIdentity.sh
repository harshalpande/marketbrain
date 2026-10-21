#!/usr/bin/env bash
# One-time, account-scoped SSH restriction. No proxy start or broker credentials.

tg_stop() { printf 'STOP: %s\n' "$*" >&2; return 1; }
tg_key() {
    printf '%s\n' 'restrict,port-forwarding,permitopen="127.0.0.1:18888",command="/usr/sbin/nologin" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0RPkYq7LMb/7fELzlnQIopM+xrLgxF1gBljdHiEdKJ marketbrain-paytm-gateway'
}
tg_block() {
    cat <<'POLICY'

# BEGIN MarketBrain forwarding-only identity
Match User marketbrain-gateway
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    HostbasedAuthentication no
    GSSAPIAuthentication no
    AuthorizedKeysFile /etc/ssh/marketbrain-gateway/authorized_keys
    AuthorizedKeysCommand none
    TrustedUserCAKeys none
    AllowTcpForwarding local
    PermitOpen 127.0.0.1:18888
    PermitListen none
    AllowStreamLocalForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PermitTunnel no
    PermitUserRC no
    MaxSessions 0
    ForceCommand /usr/sbin/nologin
# END MarketBrain forwarding-only identity
POLICY
}
tg_expected() {
    printf '%s\n' 'authenticationmethods publickey' 'pubkeyauthentication yes' \
        'passwordauthentication no' 'kbdinteractiveauthentication no' \
        'hostbasedauthentication no' 'gssapiauthentication no' \
        'authorizedkeysfile /etc/ssh/marketbrain-gateway/authorized_keys' \
        'authorizedkeyscommand none' 'trustedusercakeys none' \
        'allowtcpforwarding local' 'permitopen 127.0.0.1:18888' 'permitlisten none' \
        'allowstreamlocalforwarding no' 'allowagentforwarding no' 'x11forwarding no' \
        'permittty no' 'permittunnel no' 'permituserrc no' 'maxsessions 0' \
        'forcecommand /usr/sbin/nologin' 'strictmodes yes' 'usepam yes' \
        'usedns no' 'disableforwarding no' 'chrootdirectory none'
}
tg_policy() {
    local policy="$1" line
    while IFS= read -r line; do
        [[ $'\n'"$policy"$'\n' == *$'\n'"$line"$'\n'* ]] || { tg_stop "Effective gateway policy mismatch: $line"; return 1; }
    done < <(tg_expected)
    if [[ "$policy" =~ (^|$'\n')(allowusers|denyusers|allowgroups|denygroups)[[:space:]] ]]; then
        tg_stop 'User/group lists need separate review'; return 1
    fi
}
tg_absent() {
    local rc
    if timeout 10s getent "$1" "$2" >/dev/null; then
        tg_stop "Existing $1 entry: $2; do not overwrite or rerun"; return 1
    else rc=$?; fi
    [ "$rc" = 2 ] || { tg_stop "Lookup failed ($rc); absence not established"; return 1; }
}
tg_new() { [ ! -e "$1" ] && [ ! -L "$1" ] || { tg_stop "Existing path: $1"; return 1; }; }
tg_owned() {
    local mode
    [ ! -L "$1" ] && [ "$(stat -c %u "$1")" = 0 ] || { tg_stop "Unsafe owner/symlink: $1"; return 1; }
    mode=$(stat -c %a "$1") || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || { tg_stop "Writable by non-root: $1"; return 1; }
}
tg_config_text() {
    # Conservatively support the observed standard layout only. No existing Match
    # scopes or nested/custom Includes: candidate policy must be explainable.
    awk -v main="$2" '
      /^[[:space:]]*(#|$)/ {next}
      { k=tolower($1) }
      k=="match" {exit 1}
      k=="include" && !(main=="yes" && NF==2 && $2=="/etc/ssh/sshd_config.d/*.conf") {exit 1}
    ' "$1" || { tg_stop "Existing Match or unsupported Include in $1; no SSH edit allowed"; return 1; }
}
tg_defaults() {
    # Debian commonly spells this as SSHD_OPTS=, with no quotes.
    awk '/^[[:space:]]*(#|$)/ {next} /^[[:space:]]*SSHD_OPTS=(""|'"''"')?[[:space:]]*$/ {next} {exit 1}' "$1" || { tg_stop 'Nonempty/custom SSH defaults require review'; return 1; }
}
tg_manifest() (
    set -euo pipefail
    shopt -s nullglob
    local file
    tg_owned /etc/ssh || return 1
    tg_owned /etc/ssh/sshd_config.d || return 1
    for file in /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$file" ] || return 1
        tg_owned "$file" || return 1
        tg_config_text "$file" no || return 1
        stat -c '%n %u %g %a %s' "$file" || return 1
        sha256sum "$file" || return 1
    done
)
tg_effective() { timeout 10s /usr/sbin/sshd -T -f "$1" -C "user=$2,host=$TG_CLIENT,addr=$TG_CLIENT,laddr=$TG_SERVER,lport=$TG_PORT"; }
tg_compare() {
    local current
    current=$(tg_effective "$1" root) || return 1
    [ "$current" = "$TG_ROOT_POLICY" ] || { tg_stop 'Root effective policy changed'; return 1; }
    current=$(tg_effective "$1" marketbrain-admin) || return 1
    [ "$current" = "$TG_ADMIN_POLICY" ] || { tg_stop 'Administrator effective policy changed'; return 1; }
    current=$(tg_effective "$1" marketbrain-gateway) || return 1
    tg_policy "$current"
}
tg_hash() { sha256sum "$1" | awk '{print $1}'; }
tg_same_hash() { [ "$(tg_hash "$1")" = "$2" ] || { tg_stop "File drift: $1"; return 1; }; }
tg_proxy_stopped() {
    local state listeners
    state=$(systemctl show marketbrain-paytm-gateway.service -p ActiveState --value) || return 1
    [ "$state" = inactive ] || { tg_stop 'Proxy must remain stopped'; return 1; }
    listeners=$(ss -H -ltn 'sport = :18888') || return 1
    [ -z "$listeners" ] || { tg_stop 'Port 18888 unexpectedly listening'; return 1; }
}
tg_rollback() {
    # Never overwrite another administrator's edit. Key is removed from service
    # before rollback; the new account/directories are retained for diagnosis.
    local live="${1:-/etc/ssh/sshd_config}" key="${2:-/etc/ssh/marketbrain-gateway/authorized_keys}" includes
    printf 'Attempting bounded recovery; no SSH restart or account deletion.\n'
    if [ -f "$key" ]; then
        if cmp -s "$key" <(tg_key); then mv -- "$key" "$TG_WORK/disabled-authorized_keys" || return 1
        else tg_stop 'Key drift: manual recovery required'; return 1; fi
    fi
    if tg_same_hash "$live" "$TG_OLD_HASH" >/dev/null 2>&1; then return 0; fi
    tg_same_hash "$live" "$TG_NEW_HASH" || return 1
    includes=$(tg_manifest) || return 1
    [ "$includes" = "$TG_INCLUDES" ] || { tg_stop 'Included configuration drift; preserve files for manual recovery'; return 1; }
    timeout 10s /usr/sbin/sshd -t -f "$TG_WORK/original" || return 1
    cp --preserve=all -- "$TG_WORK/original" "$TG_WORK/restore" || return 1
    mv -T -- "$TG_WORK/restore" "$live" || return 1
    timeout 20s systemctl reload ssh.service || return 1
    timeout 10s systemctl is-active --quiet ssh.service || return 1
    printf 'Original SSH file restored/reloaded. New account retained without its authorized key.\n'
}
tg_exit() {
    local rc="$1"
    trap - EXIT
    if [ "$rc" -ne 0 ]; then
        if [ "$TG_CHANGED" = yes ]; then
            if ! tg_rollback; then printf 'RECOVERY NOT CONFIRMED: retain root/admin windows; use provider console if needed.\n'; fi
        fi
        printf 'FAILED exit=%s. Do not rerun. Private backup/work directory: %s\n' "$rc" "${TG_WORK:-not-created}"
    fi
    return "$rc"
}
tg_install() (
    set -Eeuo pipefail
    TG_CHANGED=no TG_WORK=''
    trap 'tg_exit "$?"' EXIT
    trap 'printf "FAILED line=%s command=%s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
    local config=/etc/ssh/sshd_config name=marketbrain-gateway answer fp unitopts defaults
    local client_port extra include_now
    printf '[0%%] Checking verified VPS, SSH launch/configuration and key separation.\n'
    for tool in timeout getent stat ssh-keygen sshd useradd install grep awk tee mktemp flock cmp sha256sum systemctl cp mv sudo ss; do
        command -v "$tool" >/dev/null || { tg_stop "Missing tool: $tool"; exit 1; }
    done
    grep -qx 'ID=debian' /etc/os-release
    fp=$(timeout 10s ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub | awk '{print $2}')
    [ "$fp" = 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI' ] || { tg_stop 'VPS identity mismatch'; exit 1; }
    fp=$(tg_key | ssh-keygen -l -E sha256 -f /dev/stdin | awk '{print $2}')
    [ "$fp" = 'SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI' ] || { tg_stop 'Gateway public key mismatch'; exit 1; }
    local admin_keys
    admin_keys=$(ssh-keygen -l -E sha256 -f /home/marketbrain-admin/.ssh/authorized_keys)
    if grep -Fq "$fp" <<< "$admin_keys"; then tg_stop 'Gateway key duplicates administrator key'; exit 1; fi
    printf 'Gateway public key: %s (different from administrator key).\n' "$fp"
    exec 9>/run/marketbrain-gateway-identity.lock
    flock -n 9 || { tg_stop 'Another installation is running'; exit 1; }
    tg_absent passwd "$name"; tg_absent group "$name"
    tg_new /etc/ssh/marketbrain-gateway; tg_new /var/lib/marketbrain-gateway
    [ -x /usr/sbin/nologin ]
    [ -n "${SSH_CONNECTION:-}" ] || { tg_stop 'Use verified PuTTY administrator session'; exit 1; }
    read -r TG_CLIENT client_port TG_SERVER TG_PORT extra <<< "$SSH_CONNECTION"
    [[ "$TG_CLIENT" =~ ^[0-9a-fA-F:.]+$ && "$TG_SERVER" =~ ^[0-9a-fA-F:.]+$ && "$TG_PORT" = 22 && -z "$extra" ]]
    tg_owned "$config"; [ -f "$config" ]
    tg_config_text "$config" yes
    TG_INCLUDES=$(tg_manifest)
    # Refuse custom launch flags instead of testing a configuration the listener ignores.
    [ -z "$(systemctl show ssh.service -p DropInPaths --value)" ]
    [ -z "$(systemctl show ssh.service -p Environment --value)" ]
    unitopts=$(systemctl show ssh.service -p ExecStart --value)
    [[ "$unitopts" == *'argv[]=/usr/sbin/sshd -D $SSHD_OPTS ;'* ]] || { tg_stop 'Custom SSH ExecStart requires review'; exit 1; }
    defaults=$(systemctl show ssh.service -p EnvironmentFiles --value)
    [ "$defaults" = '/etc/default/ssh (ignore_errors=yes)' ] || { tg_stop 'Unexpected SSH environment files'; exit 1; }
    tg_owned /etc/default/ssh
    # Do not source a shell environment file from a diagnostic/installer.
    tg_defaults /etc/default/ssh
    timeout 10s /usr/sbin/sshd -t
    timeout 10s systemctl is-active --quiet ssh.service
    tg_proxy_stopped
    TG_ROOT_POLICY=$(tg_effective "$config" root)
    TG_ADMIN_POLICY=$(tg_effective "$config" marketbrain-admin)
    grep -Fxq 'usedns no' <<< "$TG_ADMIN_POLICY"
    # Before the Match block exists, a new account must not inherit an external
    # key command or certificate authority that could authenticate it early.
    grep -Fxq 'authorizedkeyscommand none' <<< "$TG_ADMIN_POLICY"
    grep -Fxq 'trustedusercakeys none' <<< "$TG_ADMIN_POLICY"
    TG_OLD_HASH=$(tg_hash "$config")
    printf '[20%%] Preflight passed. Creates one forwarding-only account and appends one Match User block.\n'
    printf 'Preserves root/admin policies, backs up SSH config, validates candidate, reloads (never restarts) SSH.\n'
    printf 'Keep both existing administrator/root sessions and provider console available.\n'
    printf 'Type INSTALL-TUNNEL to continue: ' >/dev/tty
    read -r answer </dev/tty
    [ "$answer" = INSTALL-TUNNEL ] || { tg_stop 'Not confirmed; no account/config changes'; exit 1; }
    # Backup under /etc/ssh guarantees atomic same-filesystem replacement. Not a drop-in.
    TG_WORK=$(mktemp -d /etc/ssh/marketbrain-tunnel-backup-XXXXXXXX)
    cp --preserve=all -- "$config" "$TG_WORK/original"
    cp --preserve=all -- "$config" "$TG_WORK/candidate"
    tg_block >> "$TG_WORK/candidate"
    tg_same_hash "$TG_WORK/original" "$TG_OLD_HASH"
    timeout 10s /usr/sbin/sshd -t -f "$TG_WORK/candidate"
    tg_compare "$TG_WORK/candidate"
    TG_NEW_HASH=$(tg_hash "$TG_WORK/candidate")
    printf '[45%%] Candidate syntax/restrictions pass; root/admin effective policies unchanged.\n'
    tg_absent passwd "$name"; tg_absent group "$name"
    tg_new /etc/ssh/marketbrain-gateway; tg_new /var/lib/marketbrain-gateway
    # Invalid password hash, no password login. Debian UsePAM=yes is explicitly checked.
    useradd --system --user-group --no-create-home --home-dir /var/lib/marketbrain-gateway --shell /usr/sbin/nologin --password '*' "$name"
    [ "$(id -Gn "$name")" = "$name" ] || { tg_stop 'Unexpected group membership'; exit 1; }
    install -d -o root -g root -m 755 /etc/ssh/marketbrain-gateway
    # Candidate is evaluated again now the account exists (NSS/group lookup).
    tg_compare "$TG_WORK/candidate"
    tg_same_hash "$config" "$TG_OLD_HASH"
    include_now=$(tg_manifest)
    [ "$include_now" = "$TG_INCLUDES" ] || { tg_stop 'Included configuration changed'; exit 1; }
    TG_CHANGED=yes
    mv -T -- "$TG_WORK/candidate" "$config"
    timeout 10s /usr/sbin/sshd -t
    timeout 20s systemctl reload ssh.service
    timeout 10s systemctl is-active --quiet ssh.service
    tg_compare "$config"
    printf '[75%%] Account restriction reloaded; now installing its root-owned public key.\n'
    tg_key > "$TG_WORK/key"
    install -o root -g root -m 644 "$TG_WORK/key" /etc/ssh/marketbrain-gateway/authorized_keys
    cmp -s /etc/ssh/marketbrain-gateway/authorized_keys <(tg_key)
    [ "$(stat -c '%U:%G:%a' /etc/ssh/marketbrain-gateway/authorized_keys)" = root:root:644 ]
    tg_owned /etc/ssh/marketbrain-gateway
    # Concrete privilege denial probe; exit 1 (not arbitrary failure) is expected.
    if timeout 10s sudo -u "$name" sudo -n /usr/bin/true >/dev/null 2>&1; then
        tg_stop 'Unexpected passwordless sudo grant'; exit 1
    else [ "$?" = 1 ]; fi
    tg_same_hash "$config" "$TG_NEW_HASH"
    include_now=$(tg_manifest)
    [ "$include_now" = "$TG_INCLUDES" ]
    tg_proxy_stopped
    printf 'Backup (private, do not share contents): %s/original\n' "$TG_WORK"
    printf 'SSH config before=%s after=%s\n' "$TG_OLD_HASH" "$TG_NEW_HASH"
    printf '[100%%] TUNNEL_IDENTITY_INSTALLED_FRESH_ADMIN_LOGIN_AND_TUNNEL_TESTS_PENDING\n'
    printf 'Proxy remains stopped. No firewall/routes, application, broker credentials or trades changed.\n'
    printf 'Open a fresh marketbrain-admin PuTTY login with the ORIGINAL key and verify sudo whoami.\n'
    printf 'Do not test gateway with a normal shell: shell sessions are intentionally prohibited.\n'
)
tg_main() (
    set -Eeuo pipefail
    export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin
    umask 077
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] || { tg_stop 'Run only on VPS as root via verified administrator'; exit 1; }
    local report start result
    report=$(mktemp /tmp/marketbrain-tunnel-identity-XXXXXXXX.log)
    start=$SECONDS
    printf 'Share this ONE log: %s\n' "$report"
    set +e
    tg_install 2>&1 | tee "$report"
    result=("${PIPESTATUS[@]}")
    set -e
    printf 'Finished exit=%s logExit=%s elapsed=%ss; report=%s\n' "${result[0]}" "${result[1]}" "$((SECONDS-start))" "$report" | tee -a "$report"
    [ "${result[0]}" = 0 ] && [ "${result[1]}" = 0 ]
)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then tg_main "$@"; fi
