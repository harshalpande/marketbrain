#!/usr/bin/env bash
# Local observations only. Writes one private temporary report, not system configuration.
set -u
set -o pipefail
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

gateway_check() {
    local label="$1" rc
    shift
    printf '\n--- %s ---\n' "$label"
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'UNAVAILABLE: %s (not installed or not on PATH; not evidence of disabled protection)\n' "$1"
        return 0
    fi
    if timeout --signal=TERM --kill-after=2s 10s "$@"; then rc=0; else rc=$?; fi
    printf 'COMMAND_EXIT=%s\n' "$rc"
    # Diagnostic failures are evidence to review, not permission to install or reconfigure.
    return 0
}

gateway_snapshot() {
    printf 'MARKETBRAIN_GATEWAY_BASELINE_V1\n'
    printf 'UTC: '; date -u '+%Y-%m-%dT%H:%M:%SZ'
    printf 'READ_ONLY_INSPECTION; NO_PROVIDER_CALLS; NO_CONFIGURATION_CHANGES\n'
    printf '[10%%] Identity and resources\n'
    gateway_check 'Existing RSA host-key fingerprint' ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key.pub
    gateway_check 'Operating system' cat /etc/os-release
    gateway_check 'Kernel and architecture' uname -srmo
    gateway_check 'CPU count' nproc
    gateway_check 'Memory and swap' free -h
    gateway_check 'Root filesystem space' df -h /
    printf '\n[40%%] Interfaces, routes and listeners (not an external reachability test)\n'
    gateway_check 'Interface addresses' ip -brief address show
    gateway_check 'IPv4 routes' ip -4 route show
    gateway_check 'IPv6 routes' ip -6 route show
    gateway_check 'Listening TCP and UDP sockets' ss -H -lntu
    printf '\n[65%%] Gateway prerequisites and installed tools\n'
    if [ -c /dev/net/tun ]; then printf 'TUN_DEVICE_PRESENT\n'; else printf 'TUN_DEVICE_MISSING\n'; fi
    gateway_check 'Forwarding state only' sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
    gateway_check 'Tailscale version only; no login/status dump' tailscale version
    gateway_check 'nftables table inventory only; NOT full policy assessment' nft list tables
    gateway_check 'iptables version only; NOT full policy assessment' iptables --version
    gateway_check 'UFW status' ufw status
    printf '\n[85%%] SSH configuration syntax and selected base policy\n'
    gateway_check 'SSH syntax test (does not restart SSH)' sshd -t
    # Filter before publishing: do not dump full SSH config, command hooks or environment.
    printf '\n--- Selected SSH base settings; Match-specific policy NOT evaluated ---\n'
    timeout --signal=TERM --kill-after=2s 10s sshd -T 2>/dev/null |
        awk '$1 ~ /^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|authenticationmethods|allowtcpforwarding|gatewayports)$/ {print}'
    printf 'FILTERED_SSH_PIPELINE_EXIT=%s\n' "$?"
    printf '\n[100%%] CAPTURED_REVIEW_REQUIRED\n'
    printf 'Missing commands/nonzero exits require review. No gateway or firewall pass is implied.\n'
    printf 'Provider firewall, effective SSH Match rules, internet egress and fail-closed routing remain untested.\n'
}

gateway_main() {
    local report started rc
    if [ "$(uname -s)" != Linux ] || [ "$(id -u)" != 0 ]; then
        printf 'STOP: run on the verified Debian VPS as root, not Windows or the application laptop.\n' >&2
        return 1
    fi
    for dependency in timeout mktemp tee awk; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            printf 'STOP: required utility missing: %s. No automatic installation.\n' "$dependency" >&2
            return 1
        fi
    done
    umask 077
    report=$(mktemp /tmp/marketbrain-gateway-baseline-XXXXXXXX.log) || return 1
    started=$SECONDS
    gateway_snapshot 2>&1 | tee "$report"
    rc=$?
    printf 'ELAPSED_SECONDS=%s\nREPORT_PIPELINE_EXIT=%s\n' "$((SECONDS-started))" "$rc" | tee -a "$report"
    printf 'Share this ONE report: %s\n' "$report"
    return "$rc"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then gateway_main; fi
