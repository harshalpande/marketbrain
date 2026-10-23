#!/usr/bin/env bash
# Fixed six-package transaction. Never replay an existing stage or reboot.
si_expected() {
    printf '%s\n' 'libintl-perl|1.35-1|all' 'libmodule-find-perl|0.17-1|all' 'libproc-processtable-perl|0.636-1+b3|amd64' 'libsort-naturally-perl|1.03-4|all' 'libterm-readkey-perl|2.38-2+b4|amd64' 'needrestart|3.11-1|all'
}
si_fail() { failure_code="$1"; printf 'SCANNER_INSTALL_STOP=%s\n' "$1" >&2; exit 1; }
si_arguments() {
    local package version architecture
    packages=(); targets=()
    while IFS='|' read -r package version architecture; do packages+=("$package");targets+=("$package=$version");done < <(si_expected)
    [ "${#packages[@]}" = 6 ]
}
si_absent() {
    local p rows code
    for p in "${packages[@]}"; do
        code=0;rows=$(timeout 10s dpkg-query -W '-f=${db:Status-Abbrev}' "$p" 2>/dev/null) || code=$?
        if [ "$code" = 1 ] && [ -z "$rows" ]; then continue;fi
        [ "$code" = 0 ] && [ "$rows" = 'un ' ] || return 1
    done
    [ ! -e /etc/needrestart ] && [ ! -L /etc/needrestart ]
}
si_versions() {
    local rows
    rows=$(timeout 30s dpkg-query -W '-f=${Package}|${db:Status-Abbrev}|${Version}|${Architecture}\n' "${packages[@]}") || return 1
    rows=$(printf '%s\n' "$rows" | awk -F'|' 'NF!=4 || $2!="ii " {exit 2} {print $1 "|" $3 "|" $4}' | sort) || return 1
    [ "$rows" = "$(si_expected | sort)" ]
}
si_plan() {
    local rows expected
    rows=$(printf '%s\n' "$1" | psp_actions | sort) || return 1
    expected=$(si_expected | awk -F'|' '{print "I|" $1 "|NOT_INSTALLED|" $2;print "C|" $1 "|NOT_APPLICABLE|" $2}' | sort) || return 1
    [ "$rows" = "$expected" ]
}
si_source_text_safe() {
    # Any per-source authentication/expiry override needs review, including deb822.
    # Consume the entire stream: grep -q plus pipefail could fail open on SIGPIPE.
    local code=0
    printf '%s\n' "$1" | sed 's/#.*//' | tr '[]' '  ' | grep -Ei '(^|[[:space:]])(trusted|allow-insecure|allow-weak|allow-downgrade-to-insecure|check-valid-until|check-date)[[:space:]]*[:=]' >/dev/null || code=$?
    [ "$code" = 1 ]
}
si_sources() (
    shopt -s nullglob
    local path rows count=0
    pb_parent /etc/apt && pb_parent /etc/apt/sources.list.d || return 1
    for path in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        if [ ! -e "$path" ] && [ ! -L "$path" ];then continue;fi
        [ -f "$path" ] && [ ! -L "$path" ] && [ "$(stat -c %u "$path")" = 0 ] && [ "$(stat -c %s "$path")" -le 1048576 ] || return 1
        rows=$(timeout 10s cat "$path") && si_source_text_safe "$rows" || return 1
        count=$((count+1));[ "$count" -le 30 ] || return 1
    done
    [ "$count" -gt 0 ]
)
si_origins() {
    # Private empty cache makes print-uris enumerate all six downloads. No URI text in shared receipt.
    local row uri filename size digest extra count=0 total=0
    local -A seen=()
    while IFS= read -r row; do
        [[ "$row" = "'"* ]] || continue
        read -r uri filename size digest extra <<<"$row"
        [[ "$uri" = "'"*"'" && "$filename" =~ ^[A-Za-z0-9.+%:~_-]+\.deb$ && "$size" =~ ^[0-9]{1,9}$ && -z "$extra" ]] || return 1
        uri="${uri:1:${#uri}-2}"
        [[ "$uri" =~ ^https?://(deb\.debian\.org/(debian|debian-security)|security\.debian\.org/debian-security)/pool/[A-Za-z0-9/._+%~:-]+\.deb$ ]] || return 1
        [[ "$digest" =~ ^(MD5Sum|SHA256|SHA512):[a-fA-F0-9]+$ ]] || return 1
        [ -z "${seen[$filename]:-}" ] || return 1;seen[$filename]=yes
        count=$((count+1));total=$((total+10#$size));[ "$count" -le 6 ] && [ "$total" -le 52428800 ] || return 1
    done <<<"$1"
    [ "$count" = 6 ] && [ "$total" -gt 0 ]
}
si_backup() {
    local size free rows path
    for path in /etc /var/lib/dpkg /var/lib/apt/extended_states; do
        [ -e "$path" ] && [ ! -L "$path" ] && [ "$(realpath -e "$path")" = "$path" ] || return 1
    done
    rows=$(timeout 30s du --apparent-size -skc /etc /var/lib/dpkg /var/lib/apt/extended_states) || return 1
    size=$(printf '%s\n' "$rows" | tail -1 | awk '{print $1}')
    rows=$(timeout 10s df -Pk "$directory") || return 1;free=$(printf '%s\n' "$rows" | awk 'NR==2 {print $4}')
    [[ "$size" =~ ^[0-9]{1,9}$ && "$free" =~ ^[0-9]{1,12}$ ]] && [ "$size" -gt 0 ] && [ "$size" -le 524288 ] && [ "$free" -ge "$((2*size+1048576))" ] || return 1
    pb_archive / "$directory" etc var/lib/dpkg var/lib/apt/extended_states || return 1
    sha256sum /var/lib/dpkg/status >"$directory/dpkg-status.sha256"
}
si_archive_rows() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local path package version architecture rows='' count=0 directory="$1"
    while IFS= read -r path; do
        [[ "$path" = "$directory/archives/"*.deb ]] && [ -f "$path" ] && [ ! -L "$path" ] || exit 1
        package=$(timeout 10s dpkg-deb -f "$path" Package) || exit 1
        version=$(timeout 10s dpkg-deb -f "$path" Version) || exit 1
        architecture=$(timeout 10s dpkg-deb -f "$path" Architecture) || exit 1
        rows+="$package|$version|$architecture"$'\n';count=$((count+1));[ "$count" -le 6 ] || exit 1
    done
    [ "$count" = 6 ] && [ "$(printf '%s' "$rows" | sort)" = "$(si_expected | sort)" ]
)
si_hook() (
    set -uo pipefail; export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local directory=/var/backups/marketbrain-maintenance/scanner-install-20261023
    local -a packages targets
    si_archive_rows "$directory" || exit 1
    si_arguments && si_absent && pr_targets && sha256sum --check --status "$directory/dpkg-status.sha256"
)
si_list_config() {
    local path=/etc/needrestart/conf.d/99-marketbrain-list-only.conf
    pb_parent /etc/needrestart && pb_parent /etc/needrestart/conf.d || return 1
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
    (set -o noclobber; printf '%s\n' "\$nrconf{restart} = 'l';" >"$path") || return 1
    chmod 600 "$path" && [ "$(stat -c '%u:%g:%a' "$path")" = 0:0:600 ] && [ "$(cat "$path")" = "\$nrconf{restart} = 'l';" ]
}
si_receipt() {
    printf 'BEGIN_PAYTM_SCANNER_INSTALL_%s\nVERSION=1\nRUN_ID=%s\n' "$run" "$run"
    printf 'PHASE=%s\nEXIT_CODE=%s\nINSTALL_ATTEMPTED=%s\nPOSTCHECKS_PASSED=%s\n' "$phase" "$1" "$attempted" "$post"
    printf 'ORIGINS_VERIFIED=%s\nLIST_ONLY_CONFIGURED=%s\nREVIEW_B64=%s\nFAILURE_CODE=%s\n' "$origins" "$configured" "$review" "$failure_code"
    printf 'CAPTURE_COMPLETE=yes\nEND_PAYTM_SCANNER_INSTALL_%s\n' "$run"
}
si_phase() { phase="$1";printf '%s\n' "$phase" >"$directory/phase" || si_fail STATE_WRITE; }
si_scanner_available() { [ -x /usr/sbin/needrestart ]; }
si_execute() {
    mu_guard && pr_targets && si_arguments && si_absent || si_fail GUARD
    [ "$(dpkg --print-architecture)" = amd64 ] || si_fail ARCHITECTURE
    [ "$(po_value timedatectl show -p NTPSynchronized --value)" = yes ] || si_fail TIME_HEALTH
    si_sources || si_fail APT_TRUST_CONFIGURATION
    si_phase BACKUP;si_backup || si_fail BACKUP
    si_phase REFRESH
    timeout --kill-after=10s 180s apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any update || si_fail INDEX_REFRESH
    si_phase SIMULATE
    timeout --kill-after=5s 60s apt-get "${apt_options[@]}" -s --no-install-recommends --no-remove install needrestart >"$directory/candidate-plan.txt" || si_fail SIMULATION_FAILED
    si_plan "$(cat "$directory/candidate-plan.txt")" || si_fail CANDIDATE_PLAN_CHANGED
    timeout --kill-after=5s 60s apt-get "${apt_options[@]}" -s --no-install-recommends --no-remove install "${targets[@]}" >"$directory/exact-plan.txt" || si_fail SIMULATION_FAILED
    si_plan "$(cat "$directory/exact-plan.txt")" || si_fail EXACT_PLAN_CHANGED
    timeout --kill-after=5s 60s apt-get "${apt_options[@]}" --print-uris --download-only --assume-yes --no-remove --no-install-recommends install "${targets[@]}" >"$directory/uris.txt" || si_fail URI_QUERY
    si_origins "$(cat "$directory/uris.txt")" || si_fail ORIGIN_OR_SIZE_REVIEW;origins=yes
    si_phase DOWNLOAD
    timeout --kill-after=10s 300s apt-get "${apt_options[@]}" --download-only --assume-yes --no-remove --no-install-recommends install "${targets[@]}" || si_fail DOWNLOAD
    mu_guard && pr_targets && si_absent && si_sources && sha256sum --check --status "$directory/dpkg-status.sha256" || si_fail PREINSTALL_DRIFT
    si_phase INSTALL;attempted=yes
    # Do not kill dpkg on a timer. NEEDRESTART_SUSPEND suppresses the new APT hook.
    apt-get "${apt_options[@]}" --no-download --assume-yes --no-remove --no-install-recommends \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o "DPkg::Pre-Install-Pkgs::=/bin/bash $directory/worker.sh hook" install "${targets[@]}" || si_fail INSTALL_FAILED_NO_AUTO_REPAIR
    si_phase POSTCHECK
    si_versions && pr_targets && mu_guard || si_fail POSTCHECK
    si_list_config || si_fail LIST_ONLY_CONFIG;configured=yes
    [ "$(po_value timedatectl show -p NTPSynchronized --value)" = yes ] || si_fail TIME_HEALTH
    si_scanner_available || si_fail SCANNER_NOT_AVAILABLE
    post=yes;si_phase SCAN
    timeout --kill-after=5s 420s /bin/bash "$directory/worker.sh" scan >"$directory/restart-review.txt" || si_fail SCAN_FAILED
    rows=$(awk '/^BEGIN_PAYTM_RESTART_/ {capture=1} capture {print} /^END_PAYTM_RESTART_/ {capture=0}' "$directory/restart-review.txt")
    [[ "$rows" = "BEGIN_PAYTM_RESTART_$run"$'\n'* && "$rows" = *$'\n'"END_PAYTM_RESTART_$run" ]] && [ "${#rows}" -le 40000 ] || si_fail SCAN_RECEIPT
    review=$(printf '%s\n' "$rows" | base64 -w 0);si_phase COMPLETE
}
si_worker() (
    set -uo pipefail;umask 077
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C SUDO_USER=marketbrain-admin DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 UCF_FORCE_CONFFOLD=1
    unset TAR_OPTIONS APT_CONFIG
    local run="$1" directory=/var/backups/marketbrain-maintenance/scanner-install-20261023
    local phase=PRECHECK attempted=no post=no origins=no configured=no review=NONE failure_code=NONE rows
    local -a packages targets apt_options=(-o DPkg::Lock::Timeout=30 -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20
        -o APT::Get::AllowUnauthenticated=false -o Acquire::AllowInsecureRepositories=false -o Acquire::AllowDowngradeToInsecureRepositories=false
        -o Acquire::Check-Valid-Until=true -o Acquire::Check-Date=true -o Acquire::https::Verify-Peer=true -o Acquire::https::Verify-Host=true
        -o Dir::Etc::sourcelist=/etc/apt/sources.list -o Dir::Etc::sourceparts=/etc/apt/sources.list.d -o "Dir::Cache::archives=$directory/archives/")
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] || exit 1
    trap 'rc=$?; si_receipt "$rc" >"$directory/receipt.tmp"; mv -T -- "$directory/receipt.tmp" "$directory/receipt.txt"' EXIT
    si_execute
)
si_launch() (
    set -uo pipefail;export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C;umask 077
    local run="${1:-}" directory=/var/backups/marketbrain-maintenance/scanner-install-20261023
    local -a packages targets
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] && [ "${SUDO_USER:-}" = marketbrain-admin ] || return 1
    mu_guard && pr_targets && si_arguments && si_absent || si_fail LAUNCH_GUARD
    pb_parent /var && pb_parent /var/backups && pb_parent /var/backups/marketbrain-maintenance && [ "$(stat -c '%u:%g:%a' /var/backups/marketbrain-maintenance)" = 0:0:700 ] || si_fail STAGE_PARENT
    mkdir -m 700 -- "$directory" || si_fail ALREADY_STAGED_DO_NOT_RETRY
    printf '%s\n' "$run" >"$directory/run-id" || si_fail STAGE_WRITE
    printf 'STAGED\n' >"$directory/phase" || si_fail STAGE_WRITE
    mkdir -m 700 -- "$directory/archives" "$directory/archives/partial" || si_fail STAGE_WRITE
    {
        printf '#!/usr/bin/env bash\n'
        declare -f po_value po_hash po_field pb_parent pb_archive mu_guard mu_expected pr_targets pr_nr_sanitize pr_units_sanitize pm_main pr_main psp_actions si_expected si_fail si_arguments si_absent si_versions si_plan si_source_text_safe si_sources si_origins si_backup si_archive_rows si_hook si_list_config si_receipt si_phase si_scanner_available si_execute si_worker
        printf '\ncase "${1:-}" in hook) si_hook;; scan) export SUDO_USER=marketbrain-admin; pr_main %q;; run) si_worker %q;; *) exit 2;; esac\n' "$run" "$run"
    } >"$directory/worker.sh" || si_fail STAGE_WRITE
    chmod 700 "$directory/worker.sh" || si_fail STAGE_WRITE
    : >"$directory/private.log"
    timeout 20s systemd-run --unit="marketbrain-scanner-$run" --service-type=exec --remain-after-exit \
        --property=UMask=0077 --property=TimeoutStartSec=infinity --property=Restart=no \
        --property="StandardOutput=append:$directory/private.log" --property="StandardError=append:$directory/private.log" \
        /bin/bash "$directory/worker.sh" run || si_fail LAUNCH_RESULT_UNKNOWN_USE_COLLECT
    printf 'SCANNER_JOB_STARTED=%s\n' "$run"
    si_poll "$run"
)
si_poll() (
    # Observation only: never starts/stops/replays a package transaction.
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
    local run="${1:-}" directory=/var/backups/marketbrain-maintenance/scanner-install-20261023 fingerprint i phase path
    [[ "$run" =~ ^[a-f0-9]{32}$ ]] && [ "$(id -u)" = 0 ] || return 1
    fingerprint=$(po_value ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub)
    [[ "$fingerprint" == '3072 SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI '* ]] || return 1
    pb_parent /var && pb_parent /var/backups && pb_parent /var/backups/marketbrain-maintenance && pb_parent "$directory" || return 1
    [ "$(stat -c '%u:%g:%a' "$directory")" = 0:0:700 ] || return 1
    path="$directory/run-id"
    [ -f "$path" ] && [ ! -L "$path" ] && [ "$(stat -c '%u:%g:%a' "$path")" = 0:0:600 ] && [ "$(cat "$path")" = "$run" ] || return 1
    for ((i=0;i<240;i++)); do
        path="$directory/receipt.txt"
        if [ -f "$path" ] && [ ! -L "$path" ]; then
            [ "$(stat -c '%u:%g:%a' "$path")" = 0:0:600 ] && [ "$(stat -c %s "$path")" -le 60000 ] || return 1
            cat "$path";return 0
        fi
        phase=$(cat "$directory/phase" 2>/dev/null)
        case "$phase" in STAGED|PRECHECK|BACKUP|REFRESH|SIMULATE|DOWNLOAD|INSTALL|POSTCHECK|SCAN|COMPLETE) ;; *) phase=UNKNOWN;; esac
        printf '[VPS] Phase=%s; observation=%ss. Do not interrupt installation or repeat Apply.\n' "$phase" "$((i*5))"
        sleep 5
    done
    printf 'OBSERVATION_ENDED_USE_COLLECT=%s\n' "$run"
)
