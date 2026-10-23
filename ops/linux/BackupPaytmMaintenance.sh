#!/usr/bin/env bash
# Definitions only. No restore/update/restart operation exists in this file.
pb_abort() { printf 'BACKUP_STOP=%s\n' "$1" >&2; exit 1; }
pb_parent() {
    local path="$1" metadata
    [ -d "$path" ] && [ ! -L "$path" ] && [ "$(realpath -e -- "$path")" = "$path" ] || return 1
    metadata=$(stat -c '%u:%g:%a' -- "$path") || return 1
    [[ "$metadata" = 0:0:755 || "$metadata" = 0:0:700 ]]
}
pb_archive() {
    local root="$1" directory="$2"; shift 2
    [ ! -e "$directory/configuration.tar" ] && [ ! -L "$directory/configuration.tar" ] || return 1
    # Bound file growth as well as elapsed time if a source grows after the size check.
    (ulimit -f 1048576 || exit 1
     timeout --kill-after=5s 180s tar --create --acls --xattrs --numeric-owner --file "$directory/configuration.tar" --directory "$root" -- "$@") || return 1
    timeout --kill-after=5s 180s tar --compare --acls --xattrs --numeric-owner --file "$directory/configuration.tar" --directory "$root" || return 1
}
pb_receipt() {
    local code="$1"
    printf '\nBEGIN_PAYTM_BACKUP_%s\nVERSION=1\nRUN_ID=%s\n' "$run" "$run"
    printf 'PHASE=%s\nEXIT_CODE=%s\nDIRECTORY_CREATED=%s\nARCHIVE_VERIFIED=%s\n' "$phase" "$code" "$created" "$verified"
    printf 'ARCHIVE_SHA256=%s\nARCHIVE_BYTES=%s\nPACKAGE_STATE_UNCHANGED=%s\n' "$digest" "$bytes" "$unchanged"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_BACKUP_%s\n' "$run"
    if [ "$created" = yes ]; then printf 'Private files retained at %s; do not upload them.\n' "$directory"; fi
}
pb_main() (
    set -uo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    unset TAR_OPTIONS
    umask 077
    local run="${1:-}" phase=PRECHECK created=no verified=no digest=NONE bytes=0 unchanged=no
    local base=/var/backups/marketbrain-maintenance directory fingerprint rows size available before after path
    local -a sources=(etc var/lib/dpkg var/lib/apt/extended_states home/marketbrain-admin/.ssh)
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || return 1
    directory="$base/$run"
    trap 'pb_receipt $?' EXIT
    trap 'exit 124' TERM
    [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ] && [ "${SUDO_USER:-}" = marketbrain-admin ] || pb_abort IDENTITY
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || pb_abort HOST_PIN
    [ "$(po_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747)" = MATCH ] &&
    [ "$(po_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1)" = MATCH ] &&
    [ "$(po_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2)" = MATCH ] || pb_abort CONFIG_DRIFT
    [ "$(po_value systemctl show marketbrain-paytm-gateway.service -p ActiveState --value)" = inactive ] || pb_abort PROXY_ACTIVE
    rows=$(timeout 10s ss -H -ltn 'sport = :18888' 2>/dev/null) && [ -z "$rows" ] || pb_abort LISTENER
    timeout 10s /usr/sbin/sshd -t >/dev/null 2>&1 || pb_abort SSH_CONFIG
    rows=$(timeout 20s dpkg --audit 2>/dev/null) && [ -z "$rows" ] || pb_abort PACKAGE_HEALTH
    pb_parent /var && pb_parent /var/backups || pb_abort BACKUP_PARENT
    for path in "${sources[@]}"; do
        [ -e "/$path" ] && [ ! -L "/$path" ] && [ "$(realpath -e -- "/$path")" = "/$path" ] || pb_abort SOURCE_PATH
    done
    # Measure apparent bytes, including sparse logical size; cap scope at512MiB.
    rows=$(timeout 30s du --apparent-size -skc -- "${sources[@]/#//}" 2>/dev/null) || pb_abort SIZE_QUERY
    size=$(printf '%s\n' "$rows" | tail -1 | awk '{print $1}')
    [[ "$size" =~ ^[0-9]{1,9}$ ]] && [ "$size" -gt 0 ] && [ "$size" -le 524288 ] || pb_abort SOURCE_SIZE
    rows=$(timeout 10s df -Pk /var/backups 2>/dev/null) || pb_abort SPACE_QUERY
    available=$(printf '%s\n' "$rows" | awk 'NR==2 {print $4}')
    [[ "$available" =~ ^[0-9]{1,12}$ ]] && [ "$available" -ge "$((2*size+524288))" ] || pb_abort SPACE
    printf '[VPS 20%%] Identity/source/space checks passed. Creating private backup only.\n'
    phase=CREATE_DIRECTORY
    if [ ! -e "$base" ] && [ ! -L "$base" ]; then mkdir -m 700 -- "$base" || pb_abort BASE_CREATE; fi
    pb_parent "$base" && [ "$(stat -c '%u:%g:%a' -- "$base")" = 0:0:700 ] || pb_abort BASE_PERMISSIONS
    mkdir -m 700 -- "$directory" || pb_abort RUN_EXISTS_OR_CREATE_FAILED
    created=yes
    [ "$(stat -c '%u:%g:%a' -- "$directory")" = 0:0:700 ] || pb_abort DIRECTORY_PERMISSIONS
    phase=CAPTURE
    before=$(sha256sum -- /var/lib/dpkg/status) || pb_abort PACKAGE_HASH
    timeout 20s dpkg --get-selections '*' >"$directory/package-selections.txt" 2>"$directory/private.log" || pb_abort PACKAGE_SELECTIONS
    printf '[VPS 40%%] Creating archive and comparing it against source files; up to180 seconds per operation.\n'
    pb_archive / "$directory" "${sources[@]}" >>"$directory/private.log" 2>&1 || pb_abort ARCHIVE_OR_COMPARE
    phase=VERIFY
    after=$(sha256sum -- /var/lib/dpkg/status) || pb_abort PACKAGE_HASH
    [ "$before" = "$after" ] || pb_abort PACKAGE_DRIFT
    unchanged=yes
    [ "$(stat -c '%u:%g:%a' -- "$directory/configuration.tar")" = 0:0:600 ] || pb_abort ARCHIVE_PERMISSIONS
    digest=$(timeout 30s sha256sum -- "$directory/configuration.tar") || pb_abort ARCHIVE_HASH
    digest=${digest%% *}
    [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || pb_abort ARCHIVE_HASH
    bytes=$(stat -c %s -- "$directory/configuration.tar") || pb_abort ARCHIVE_SIZE
    [[ "$bytes" =~ ^[0-9]{1,12}$ ]] && [ "$bytes" -gt 0 ] || pb_abort ARCHIVE_SIZE
    printf '%s  configuration.tar\n' "$digest" >"$directory/SHA256SUMS" || pb_abort MANIFEST
    verified=yes; phase=COMPLETE
    printf '[VPS 100%%] Archive comparison passed. No extraction, package update or reboot performed.\n'
)
