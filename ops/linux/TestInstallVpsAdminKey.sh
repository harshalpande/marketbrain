#!/usr/bin/env bash
# Guard tests only. No account creation, packages, VPS access or system file writes.
set -eu
source "$(dirname "$0")/InstallVpsAdminKey.sh"
checks=0
pass() { checks=$((checks+1)); }
reject() { if "$@" >/dev/null 2>&1; then printf 'Unexpected success: %s\n' "$*"; exit 1; fi; pass; }
timeout() { return 2; }
mb_absent passwd fixture; pass
timeout() { return 0; }
reject mb_absent passwd fixture
timeout() { return 124; }
reject mb_absent passwd fixture
timeout() { return 1; }
reject mb_absent passwd fixture
reject mb_new_path "${BASH_SOURCE[0]}"
policy=$'usedns no\npubkeyauthentication yes\nstrictmodes yes\nauthorizedkeyscommand none\nauthenticationmethods any\nforcecommand none\nchrootdirectory none\nauthorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2'
mb_policy "$policy"; pass
reject mb_policy "${policy/usedns no/usedns yes}"
reject mb_policy "${policy/pubkeyauthentication yes/pubkeyauthentication no}"
reject mb_policy "${policy/strictmodes yes/strictmodes no}"
reject mb_policy "${policy/authenticationmethods any/authenticationmethods password}"
reject mb_policy "${policy/authorizedkeyscommand none/authorizedkeyscommand custom}"
reject mb_policy "${policy/forcecommand none/forcecommand custom}"
reject mb_policy "${policy/chrootdirectory none/chrootdirectory custom}"
reject mb_policy "${policy//.ssh\/authorized_keys/custom}"
reject mb_policy "$policy"$'\nallowusers root'
reject mb_policy "$policy"$'\ndenyusers fixture'
reject mb_policy "$policy"$'\nallowgroups root'
reject mb_policy "$policy"$'\ndenygroups fixture'
uname() { printf 'NOT_LINUX\n'; }
reject mb_main
uname() { printf 'Linux\n'; }
id() { printf '1000\n'; }
reject mb_main
printf 'PASS: %s offline guard cases. Real installation and second login NOT tested.\n' "$checks"
