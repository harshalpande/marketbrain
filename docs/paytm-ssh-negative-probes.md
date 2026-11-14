# E253: SSH rejection evidence accepted

**Current E253, 2026-11-15:** Disposable SSH rejection batch accepted in8.257s. Incorrect host identity and unregistered key both rejected; disposable files removed. All ten source hashes match8f40d5e CRLF; same advancing gateway, attempts2->2, failures0->0. No installed credentials, application access or configuration changes. Next: installed listener-conflict/failure-latching coverage, then clock/health/application no-fallback. G3.2/G3.5 remain open;13/30 (43.3%). No SSH test rerun needed.

The run instructions below are historical; do not repeat this test.

# Disposable SSH rejection probes

E252, November15,2026. The prior six TLS/proxy probes passed; do not repeat them. This next mode performs two actual SSH attempts as the elevated controller Windows identity, targeting only the existing gateway Linux username. It does not claim dedicated Windows-account behavior or supervisor failure-latching coverage.

1. Validate the existing public host-key line against the pinned fingerprint; generate a disposable RSA key never authorized on the VPS.
2. With a separate deliberately wrong known-hosts file, require host-change rejection before any key offer.
3. With the correct pinned public host key, require the generated key's exact fingerprint to be offered and then rejected with publickey permission denied. Network failures, timeouts, local key-permission errors and unexpected successful authentication do not pass.
4. Remove only four explicit generated files and their unique directory. Record cleanup even on failure. Never add the key to an agent or alter installed keys/known_hosts. No command or port forwarding is requested.
5. Verify existing installation and same advancing gateway worker before/after.

## Run on the spare laptop

Keep the existing gateway running. Open PowerShell7 as Administrator, pull main, then:

```powershell
& '.\ops\windows\TestPaytmSecurityProbeBundle.ps1' -SshNegative
```

No PuTTY, Pageant, credentials, rebuild, sign-out or shutdown. Normally1-2 minutes. Key generation is bounded to20 seconds; each of two SSH processes12 seconds; before/after gateway waits30 seconds each. Expected `SSH_REJECTIONS_PASSED_LISTENER_AND_HEALTH_PENDING`. Share the single printed `paytm-security-probes-*.json` on success or failure. No automatic retry. The two expected rejected connections may appear in VPS SSH logs.

The report does not contain keys or raw SSH stderr. `credentialsUsed=false` means no installed or broker credentials; the generated unregistered identity is explicitly test-only. Application/account access is not performed, so the collector does not claim a new account verification. Primary failures are preserved if disposable cleanup also fails; cleanup has its own result row. If cleanup fails, share the report before any further action.

## Validation and remaining work

31 local assertions include real ssh-keygen invocation with an empty passphrase passed as a distinct argument, wrong-host/no-key-offer rules, exact offered fingerprint, timeout/local-error rejection, fixed isolated options and success/failure cleanup. Privileged helper lifecycle uses mocks. Six controller workflows pass, including SSH success and failure, plus55 existing TLS/proxy assertions. Actual spare SSH evidence is pending.

No new checkpoint credit yet: G3.2 still needs remaining installed-system listener-conflict/failure-latching evidence; G3.5 clock/health/application no-fallback remains open. G1/G2/G3/G4/G5/G6=100/100/60/0/0/0%;13/30 (43.3%).
