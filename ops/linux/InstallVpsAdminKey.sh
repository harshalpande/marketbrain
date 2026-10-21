#!/usr/bin/env bash
# One-time named administrator setup. Never edits SSH configuration or existing accounts.

mb_stop() { printf 'STOP: %s\n' "$*" >&2; return 1; }
mb_absent() {
    local kind="$1" name="$2" rc
    if timeout 10s getent "$kind" "$name" >/dev/null; then
        mb_stop "Existing $kind entry: $name. Review instead of rerunning."; return 1
    else rc=$?; fi
    [ "$rc" = 2 ] || { mb_stop "Lookup failed ($rc): $kind. Absence is not established."; return 1; }
}
mb_new_path() {
    [ ! -e "$1" ] && [ ! -L "$1" ] || { mb_stop "Path already exists: $1"; return 1; }
}
mb_home_parent() {
    local owner mode
    [ -d /home ] && [ ! -L /home ] || { mb_stop 'Unsafe /home type'; return 1; }
    owner=$(stat -c %u /home) || return 1
    mode=$(stat -c %a /home) || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [ "$owner" = 0 ] && (( (8#$mode & 0022) == 0 )) || { mb_stop 'Unsafe /home owner or write permissions'; return 1; }
}
mb_policy() {
    # UseDNS=no was observed; refuse if it changes. Match Host then uses numeric source.
    local policy="$1" line
    for line in 'usedns no' 'pubkeyauthentication yes' 'strictmodes yes' 'authorizedkeyscommand none' 'authenticationmethods any' 'forcecommand none' 'chrootdirectory none'; do
        grep -Fxq "$line" <<< "$policy" || { mb_stop "SSH policy differs: $line"; return 1; }
    done
    grep -Eq '^authorizedkeysfile \.ssh/authorized_keys( |$)' <<< "$policy" || { mb_stop 'Nonstandard AuthorizedKeysFile'; return 1; }
    if grep -Eq '^(allowusers|denyusers|allowgroups|denygroups) ' <<< "$policy"; then
        mb_stop 'SSH user/group lists require explicit review'; return 1
    fi
}
mb_install() {
    local name=marketbrain-admin home=/home/marketbrain-admin policy answer
    local client client_port server server_port fingerprint
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] || { mb_stop 'Run only as root on the verified Debian VPS'; return 1; }
    for tool in timeout getent stat ssh-keygen sshd useradd usermod install apt-get grep awk tee mktemp flock cmp chmod chown; do
        command -v "$tool" >/dev/null || { mb_stop "Missing tool: $tool"; return 1; }
    done
    grep -qx 'ID=debian' /etc/os-release || { mb_stop 'Expected Debian'; return 1; }
    fingerprint=$(timeout 10s ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub | awk '{print $2}')
    [ "$fingerprint" = 'SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI' ] || { mb_stop 'VPS host identity differs'; return 1; }
    # /run is root controlled. flock prevents two copies of this installer racing.
    exec 9>/run/marketbrain-admin-setup.lock
    flock -n 9 || { mb_stop 'Another setup is running'; return 1; }
    mb_absent passwd "$name"
    mb_absent group "$name"
    mb_new_path "$home"
    mb_home_parent
    timeout 10s getent group sudo >/dev/null
    [ -n "${SSH_CONNECTION:-}" ] || { mb_stop 'Use the existing PuTTY SSH session, not VNC'; return 1; }
    read -r client client_port server server_port <<< "$SSH_CONNECTION"
    [[ "$client" =~ ^[0-9a-fA-F:.]+$ && "$server" =~ ^[0-9a-fA-F:.]+$ && "$server_port" =~ ^[0-9]+$ ]] || { mb_stop 'Unexpected SSH connection metadata'; return 1; }
    policy=$(timeout 10s sshd -T -C "user=$name,host=$client,addr=$client,laddr=$server,lport=$server_port")
    mb_policy "$policy"
    printf '%s\n' "$MB_PUBLIC_KEY" | timeout 10s ssh-keygen -l -E sha256 -f /dev/stdin
    printf '\n[20%%] Preflight passed. This installs sudo if missing and creates ONE full administrative account.\n'
    printf 'No SSH reload, root/password restriction, firewall or gateway change.\n'
    printf 'Type INSTALL to proceed: ' >/dev/tty
    read -r answer </dev/tty
    [ "$answer" = INSTALL ] || { mb_stop 'Not confirmed; no package/account changes'; return 1; }
    if ! command -v sudo >/dev/null; then
        printf '\n[35%%] Installing sudo from configured Debian package sources (no full upgrade).\n'
        timeout --kill-after=10s 300s apt-get -o DPkg::Lock::Timeout=30 -o Acquire::Retries=0 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o APT::Update::Error-Mode=any update
        DEBIAN_FRONTEND=noninteractive timeout --kill-after=10s 300s apt-get -o DPkg::Lock::Timeout=30 install -y --no-install-recommends --no-upgrade --no-remove sudo
    fi
    command -v sudo >/dev/null
    timeout 10s visudo -c
    # Recheck immediately before creating anything, including after package installation.
    mb_absent passwd "$name"
    mb_absent group "$name"
    mb_new_path "$home"
    mb_home_parent
    printf '\n[60%%] Creating account with password initially locked.\n'
    useradd --create-home --user-group --home-dir "$home" --shell /bin/bash "$name"
    [ -d "$home" ] && [ ! -L "$home" ]
    [ "$(stat -c %u "$home")" = "$(id -u "$name")" ]
    mb_new_path "$home/.ssh"
    chmod 700 "$home"
    install -d -m 700 -o "$name" -g "$name" "$home/.ssh"
    (set -o noclobber; printf '%s\n' "$MB_PUBLIC_KEY" > "$home/.ssh/authorized_keys")
    chmod 600 "$home/.ssh/authorized_keys"
    chown "$name:$name" "$home/.ssh/authorized_keys"
    usermod -aG sudo "$name"
    printf '\n[85%%] Verifying key, permissions and actual account policy.\n'
    cmp -s "$home/.ssh/authorized_keys" <(printf '%s\n' "$MB_PUBLIC_KEY")
    [ "$(stat -c '%U:%G:%a' "$home/.ssh")" = "$name:$name:700" ]
    [ "$(stat -c '%U:%G:%a' "$home/.ssh/authorized_keys")" = "$name:$name:600" ]
    timeout 10s ssh-keygen -l -E sha256 -f "$home/.ssh/authorized_keys"
    policy=$(timeout 10s sshd -T -C "user=$name,host=$client,addr=$client,laddr=$server,lport=$server_port")
    mb_policy "$policy"
    id "$name"
    timeout 10s sudo -l -U "$name"
    printf '\n[100%%] ACCOUNT_KEY_INSTALLED_PASSWORD_AND_SECOND_LOGIN_PENDING\n'
    printf 'Next, separately run: passwd marketbrain-admin\n'
    printf 'Choose a new account password privately; do not paste it or log it.\n'
    printf 'Keep root session open. Then test a NEW PuTTY key login and sudo -v / sudo whoami.\n'
    printf 'No verified second login, gateway or Paytm readiness is claimed. Do not rerun this installer.\n'
}
mb_main() (
    set -Eeuo pipefail
    export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin
    umask 077
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] || { mb_stop 'Run only on VPS as root'; exit 1; }
    # Public owner-provided key only. No private key or password belongs in this file.
    MB_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOVSxqHLjDm2skmoTLWNmCnjAA7Vh6SNf8lHqc0GSOu marketbrain-vps-admin'
    report=$(mktemp /tmp/marketbrain-admin-install-XXXXXXXX.log)
    printf 'Private setup log: %s\n' "$report"
    trap 'rc=$?; if [ "$rc" -ne 0 ]; then printf "STOPPED exit=%s; partial changes may remain. Keep root session open; share log and do not retry automatically.\n" "$rc" >&2; fi' EXIT
    mb_install 2>&1 | tee "$report"
)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then mb_main "$@"; fi
