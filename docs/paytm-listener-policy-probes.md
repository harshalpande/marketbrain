# E255: listener/policy results accepted

**Current E255, 2026-11-15:** Listener/policy report accepted:15 checks in6.439s,10 source hashes match9eb99f5 CRLF, same advancing worker. Real duplicate bind refused with AddressAlreadyInUse; isolated policy results remain separate. [Next: actual runtime listener latch, absent-tunnel Java failure and owned recovery](paytm-runtime-latch.md).23 helper assertions and six controller workflows passed locally. G3.2/G3.5 pending;13/30 (43.3%).

The earlier listener/policy handoff below is complete; do not repeat it.

# Listener and installed-policy verification

E254, November15,2026. One batch covers actual socket protection and isolated checks of the currently installed policy functions. It does not stop, restart, replace or reconfigure the gateway. Keep the existing gateway running; use PowerShell7 as Administrator. No PuTTY, Pageant, rebuild, credentials or application access.

## Checks

- Real listener enumeration must show the expected gateway child owning127.0.0.1:18889.
- The installed listener guard must reject these real rows when supplied a deliberately different expected owner (synthetic owner input, not a new production process).
- A second exclusive IPv4 socket bind to127.0.0.1:18889 must fail with AddressAlreadyInUse or AccessDenied. Only these socket errors pass, bracketed by the valid owned-listener checks. The attempted socket is always disposed. AccessDenied alone is not evidence of owner identity; the surrounding checks provide that evidence.
- Eight security reasons must leave isolated installed state-machine instances BLOCKED with STOP_OWNED_CHILD, no implicit rearm, and no broker/order authority.
- Expired health stops the child; late success cannot erase the deadline; regressed monotonic time is rejected; unverified health never becomes ready. These use synthetic elapsed-time inputs, not Windows clock changes.
- Current installation hashes and advancing same worker are checked before and after.

Only named function definitions are extracted from the hash-verified installed gateway.ps1 and transport.ps1. Production loops are not invoked. Every row records whether it used real sockets, real rows with synthetic owner, or isolated policy inputs. Installed hashes are recorded. No raw key material or broker data is read.

## Spare-laptop command

After pulling main in the spare repository:

```powershell
& '.\ops\windows\TestPaytmSecurityProbeBundle.ps1' -ListenerPolicy
```

Normally under1 minute; gateway readiness waits are bounded to30 seconds each. Expected `LISTENER_AND_POLICY_PASSED_RUNTIME_LATCH_AND_CLOCK_PENDING`. Share the single printed `paytm-security-probes-*.json` even on failure. No automatic retry/recovery. Do not combine this switch with -SshNegative.

## Scope and acceptance

This is evidence for boundary guards and installed policy, not production failure-latching, persistence of blocked state, actual clock drift, Java stale-health enforcement or no-direct-fallback. G3.2/G3.5 remain open; no checkpoint is closed by local tests. The next implementation must exercise the remaining runtime boundaries with owned cleanup and application/account protection. Existing successful SSH and TLS tests do not need repeating.

Local verification:15 batch checks, eight assertions including real sockets on an OS-assigned ephemeral local port, source-hash rejection, missing-function rejection and evidence on unexpected bind success. Nine controller workflows include pass/failure for the new mode and conflicting-mode rejection.55 existing TLS/proxy assertions also pass. Production gateway was not contacted locally.
