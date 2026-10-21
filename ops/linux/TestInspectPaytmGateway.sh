#!/usr/bin/env bash
# Offline function-level fixtures. Never probes a VPS or calls gateway_main successfully.
set -eu
source "$(dirname "$0")/InspectPaytmGateway.sh"
assert_contains() { [[ "$1" == *"$2"* ]] || { printf 'Assertion failed: %s\n' "$2" >&2; exit 1; }; }
timeout() { shift 3; "$@"; }
fixture_ok() { printf 'SYNTHETIC_OK\n'; }
fixture_fail() { return 7; }
out=$(gateway_check fixture fixture_ok)
assert_contains "$out" SYNTHETIC_OK
assert_contains "$out" COMMAND_EXIT=0
out=$(gateway_check fixture fixture_fail)
assert_contains "$out" COMMAND_EXIT=7
out=$(gateway_check fixture marketbrain_nonexistent_fixture_command)
assert_contains "$out" UNAVAILABLE
timeout() { return 124; }
out=$(gateway_check fixture fixture_ok)
assert_contains "$out" COMMAND_EXIT=124
uname() { printf 'NOT_LINUX\n'; }
if out=$(gateway_main 2>&1); then printf 'Wrong OS was accepted\n' >&2; exit 1; fi
assert_contains "$out" 'STOP:'
uname() { printf 'Linux\n'; }
id() { printf '1000\n'; }
if out=$(gateway_main 2>&1); then printf 'Non-root was accepted\n' >&2; exit 1; fi
assert_contains "$out" 'STOP:'
gateway_check() { printf 'SYNTHETIC_CHECK: %s\n' "$1"; }
timeout() { printf 'passwordauthentication yes\nforcecommand SYNTHETIC_DO_NOT_DISCLOSE\n'; }
out=$(gateway_snapshot)
assert_contains "$out" 'passwordauthentication yes'
if [[ "$out" == *SYNTHETIC_DO_NOT_DISCLOSE* ]]; then printf 'Unselected SSH field leaked\n' >&2; exit 1; fi
assert_contains "$out" '[100%] CAPTURED_REVIEW_REQUIRED'
assert_contains "$out" 'full policy assessment'
timeout() { return 124; }
out=$(gateway_snapshot)
assert_contains "$out" 'FILTERED_SSH_PIPELINE_EXIT=124'
assert_contains "$out" '[100%] CAPTURED_REVIEW_REQUIRED'
printf 'PASS: eight offline command/guard/snapshot scenarios; no VPS or real baseline execution.\n'
