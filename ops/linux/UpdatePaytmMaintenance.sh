#!/usr/bin/env bash
# Controlled transaction, launched as a transient root service; never reboot/restore.
mu_fail() { failure_code="$1"; printf 'UPDATE_STOP=%s\n' "$1" >&2; exit 1; }
mu_plan() {
    local input="$1" rows
    if printf '%s\n' "$input" | grep -q '^Remv '; then return 1; fi
    rows=$(printf '%s\n' "$input" | awk '/^Inst / {old=$3; new=$4; if(substr(old,1,1)!="[")exit 2;gsub(/[\[\]]/,"",old);sub(/^\(/,"",new);print $2 "|" old "|" new}') || return 1
    [ "$(printf '%s\n' "$rows" | sort)" = "$(mu_expected | sort)" ]
}
mu_versions() {
    local mode="$1" rows expected
    rows=$(timeout 30s dpkg-query -W '-f=${Package}|${db:Status-Abbrev}|${Version}\n' "${packages[@]}") || return 1
    rows=$(printf '%s\n' "$rows" | awk -F'|' 'NF!=3 || $2!="ii " {exit 2} {print $1 "|" $3}' | sort) || return 1
    if [ "$mode" = before ]; then expected=$(mu_expected | awk -F'|' '{print $1 "|" $2}' | sort)
    else expected=$(mu_expected | awk -F'|' '{print $1 "|" $3}' | sort); fi
    [ "$rows" = "$expected" ]
}
mu_arguments() {
    # All values originate in the committed fixed manifest; never from clipboard.
    local package old new extra
    packages=(); targets=()
    while IFS='|' read -r package old new extra; do
        [[ "$package" =~ ^[a-z0-9][a-z0-9.+-]*$ && "$old" =~ ^[A-Za-z0-9.+:~_-]+$ && "$new" =~ ^[A-Za-z0-9.+:~_-]+$ && -z "$extra" ]] || return 1
        dpkg --compare-versions "$old" lt "$new" || return 1
        packages+=("$package"); targets+=("$package=$new")
    done < <(mu_expected)
    [ "${#packages[@]}" = 70 ] && [ "$(printf '%s\n' "${packages[@]}" | sort -u | wc -l)" = 70 ]
}
mu_guard() {
    local fingerprint rows
    [ "$(id -u)" = 0 ] && [ "$(uname -s)" = Linux ] || return 1
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || return 1
    [ "$(po_hash /etc/marketbrain-paytm-gateway/proxy.conf 3d51baadfd8c07e22d30402ae2bf4210a9ae7d2eebf2ee19f834b65e5547b747)" = MATCH ] &&
    [ "$(po_hash /etc/marketbrain-paytm-gateway/allowlist d4a4b864c4d43bc452b6e8383fc0cf4085e0eab413ae6a1af983111cd5cd9ba1)" = MATCH ] &&
    [ "$(po_hash /etc/systemd/system/marketbrain-paytm-gateway.service ff80c68c452b9b5891a979296eb60f4a339bfccd76e5ac7063f6569901c7eaf2)" = MATCH ] || return 1
    [ "$(po_value systemctl show marketbrain-paytm-gateway.service -p ActiveState --value)" = inactive ] || return 1
    [ "$(po_value systemctl show marketbrain-paytm-gateway.service -p FragmentPath --value)" = /etc/systemd/system/marketbrain-paytm-gateway.service ] || return 1
    [ "$(po_value systemctl show marketbrain-paytm-gateway.service -p NeedDaemonReload --value)" = no ] || return 1
    rows=$(timeout 10s systemctl show marketbrain-paytm-gateway.service -p DropInPaths --value) && [ -z "$rows" ] || return 1
    rows=$(timeout 10s ss -H -ltn 'sport = :18888' 2>/dev/null) && [ -z "$rows" ] || return 1
    timeout 10s /usr/sbin/sshd -t || return 1
    rows=$(timeout 20s dpkg --audit) && [ -z "$rows" ] || return 1
    rows=$(timeout 10s apt-mark showhold) && [ -z "$rows" ] || return 1
}
mu_archive_hook() (
    # APT v1 hook: one archive path per line. Validate every archive before dpkg.
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local path package version rows='' count=0
    while IFS= read -r path; do
        [[ "$path" = /*.deb ]] && [ -f "$path" ] || exit 1
        package=$(timeout 10s dpkg-deb -f "$path" Package) || exit 1
        version=$(timeout 10s dpkg-deb -f "$path" Version) || exit 1
        rows+="$package|$version"$'\n'; count=$((count+1))
        [ "$count" -le 70 ] || exit 1
    done
    [ "$count" = 70 ] || exit 1
    [ "$(printf '%s' "$rows" | sort)" = "$(mu_expected | awk -F'|' '{print $1 "|" $3}' | sort)" ] || exit 1
    local -a packages targets
    mu_arguments && mu_versions before
)
mu_receipt() {
    printf 'BEGIN_PAYTM_UPDATE_%s\nVERSION=1\nRUN_ID=%s\n' "$run" "$run"
    printf 'PHASE=%s\nEXIT_CODE=%s\nINSTALL_ATTEMPTED=%s\nPOSTCHECKS_PASSED=%s\nREBOOT_MARKER=%s\n' "$phase" "$1" "$attempted" "$post" "$reboot"
    printf 'FAILURE_CODE=%s\n' "${failure_code:-NONE}"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_UPDATE_%s\n' "$run"
}
mu_execute() {
    # Uses the worker's fixed local context; split out solely for offline fixtures.
    mu_guard || mu_fail GUARD
    [ "$(po_hash "$archive" 3050d89b1eaa1db95a0ad27a3cb52b394870ffc0b57185dfa53672430587ca8c)" = MATCH ] || mu_fail BACKUP_HASH
    timeout --kill-after=5s 180s tar --compare --acls --xattrs --numeric-owner --file "$archive" --directory / || mu_fail BACKUP_SOURCE_DRIFT
    mu_arguments && mu_versions before || mu_fail INSTALLED_VERSION_DRIFT
    phase=REFRESH; printf '%s\n' "$phase" >"$directory/phase"
    timeout --kill-after=10s 180s apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any update || mu_fail INDEX_REFRESH
    phase=SIMULATE; printf '%s\n' "$phase" >"$directory/phase"
    rows=$(timeout 60s apt-get -s -o Debug::NoLocking=1 upgrade) && mu_plan "$rows" || mu_fail UPGRADE_PLAN_CHANGED
    rows=$(timeout 60s apt-get -s --only-upgrade --no-remove --no-install-recommends install "${targets[@]}") && mu_plan "$rows" || mu_fail EXACT_PLAN_CHANGED
    phase=DOWNLOAD; printf '%s\n' "$phase" >"$directory/phase"
    timeout --kill-after=10s 600s apt-get "${apt_options[@]}" --download-only --assume-yes --only-upgrade --no-remove --no-install-recommends install "${targets[@]}" || mu_fail DOWNLOAD
    mu_guard && mu_versions before || mu_fail PREINSTALL_DRIFT
    phase=INSTALL; attempted=yes; printf '%s\n' "$phase" >"$directory/phase"
    # Deliberately NO timeout around dpkg: killing package installation risks corruption.
    # The v1 hook rejects extra/missing/repeated archives or a changed installed baseline.
    apt-get "${apt_options[@]}" --no-download --assume-yes --only-upgrade --no-remove --no-install-recommends \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o "DPkg::Pre-Install-Pkgs::=/bin/bash $directory/worker.sh hook" \
        install "${targets[@]}" || mu_fail INSTALL_FAILED_NO_AUTO_REPAIR
    phase=POSTCHECK; printf '%s\n' "$phase" >"$directory/phase"
    mu_versions after && mu_guard || mu_fail POSTCHECK
    [ "$(po_value timedatectl show -p NTPSynchronized --value)" = yes ] || mu_fail TIME_HEALTH
    reboot=ABSENT; [ ! -e /var/run/reboot-required ] || reboot=PRESENT
    post=yes; phase=COMPLETE; printf '%s\n' "$phase" >"$directory/phase"
}
mu_worker() (
    set -uo pipefail
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l UCF_FORCE_CONFFOLD=1
    unset TAR_OPTIONS
    umask 077
    local run="$1" directory=/var/backups/marketbrain-maintenance/update-20261023
    local phase=PRECHECK attempted=no post=no reboot=UNKNOWN failure_code=NONE rows archive=/var/backups/marketbrain-maintenance/897a81468f7d4ac0ba034fc15797b6fa/configuration.tar
    local -a packages targets apt_options=(-o DPkg::Lock::Timeout=30 -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20)
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || exit 1
    # Trap writes an atomic, non-secret receipt. No automatic package repair/retry.
    trap 'rc=$?; mu_receipt "$rc" >"$directory/receipt.tmp"; mv -T -- "$directory/receipt.tmp" "$directory/receipt.txt"' EXIT
    mu_execute
)
mu_launch() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C; umask 077
    local run="${1:-}" directory=/var/backups/marketbrain-maintenance/update-20261023
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] && [ "${SUDO_USER:-}" = marketbrain-admin ] || return 1
    mu_guard || mu_fail LAUNCH_GUARD
    pb_parent /var && pb_parent /var/backups && pb_parent /var/backups/marketbrain-maintenance &&
        [ "$(stat -c '%u:%g:%a' /var/backups/marketbrain-maintenance)" = 0:0:700 ] || mu_fail BACKUP_PARENT
    local rows free
    rows=$(timeout 10s df -Pk /var/cache/apt/archives) || mu_fail SPACE_QUERY
    free=$(printf '%s\n' "$rows" | awk 'NR==2 {print $4}')
    [[ "$free" =~ ^[0-9]{1,12}$ ]] && [ "$free" -ge 4194304 ] || mu_fail SPACE
    mkdir -m 700 -- "$directory" || mu_fail ALREADY_STAGED_DO_NOT_RETRY
    printf '%s\n' "$run" >"$directory/run-id"
    printf 'STAGED\n' >"$directory/phase"
    {
        printf '#!/usr/bin/env bash\n'
        declare -f po_value po_hash mu_expected mu_fail mu_plan mu_versions mu_arguments mu_guard mu_archive_hook mu_receipt mu_execute mu_worker
        printf '\nif [ "${1:-}" = hook ]; then mu_archive_hook; else mu_worker %q; fi\n' "$run"
    } >"$directory/worker.sh" || mu_fail WORKER_WRITE
    chmod 700 "$directory/worker.sh" || mu_fail WORKER_MODE
    : >"$directory/private.log"
    timeout 20s systemd-run --unit="marketbrain-maintenance-$run" --service-type=exec --remain-after-exit \
        --property=UMask=0077 --property=TimeoutStartSec=infinity --property=Restart=no \
        --property="StandardOutput=append:$directory/private.log" --property="StandardError=append:$directory/private.log" \
        /bin/bash "$directory/worker.sh" || mu_fail LAUNCH_RESULT_UNKNOWN_DO_NOT_RETRY
    printf 'UPDATE_JOB_STARTED=%s\n' "$run"
    mu_poll "$run"
)
mu_poll() (
    # Read-only and reconnect-safe. Never launches/retries/kills a package operation.
    local run="${1:-}" directory=/var/backups/marketbrain-maintenance/update-20261023 i phase fingerprint
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] && [ "$(id -u)" = 0 ] || return 1
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || return 1
    [ "$(cat "$directory/run-id")" = "$run" ] || return 1
    for ((i=0;i<240;i++)); do
        if [ -f "$directory/receipt.txt" ]; then cat "$directory/receipt.txt"; return 0; fi
        phase=$(cat "$directory/phase" 2>/dev/null)
        case "$phase" in STAGED|PRECHECK|REFRESH|SIMULATE|DOWNLOAD|INSTALL|POSTCHECK|COMPLETE) ;; *) phase=UNKNOWN;; esac
        printf '[VPS] Phase=%s; elapsed observation=%ss. Do not interrupt package installation.\n' "$phase" "$((i*5))"
        sleep 5
    done
    printf 'OBSERVATION_WINDOW_ENDED_JOB_STATE_UNCONFIRMED=%s\nDo not rerun the installer or stop the service; reconnect and collect the same run.\n' "$run"
)
