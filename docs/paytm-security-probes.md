# Installed gateway: TLS and proxy rejection batch

E251, November15,2026. G3.4 is accepted; do not repeat sign-out or shutdown. This next collection sends six fixed, credential-free HEAD requests through the existing loopback gateway. No direct network fallback, gateway/task/configuration mutation, key import, application unlock, database access or broker login is performed. No PuTTY or Pageant is needed. Leave the gateway running and use elevated PowerShell7.

## Checks and acceptance

1. Allowed HTTPS control: CONNECT200, certificate verification0, HTTP200-599. Root503 proves only transport, not provider readiness.
2. Deliberately wrong TLS public-key pin: curl exit90, CONNECT200, no destination HTTP response. Unsupported pinning, certificate errors and timeouts do not pass.
3. Forbidden host and forbidden port: actual proxy403 with no destination response; an unreachable endpoint is not accepted as denial.
4. Plain HTTP: proxy403.
5. Repeat allowed HTTPS to establish continued access after the negatives.
6. Before/after verify installed hashes, advancing same worker, task and owned loopback listener. This is observation, not a guarantee of uninterrupted connectivity or all possible concurrent changes.

The requests use the Windows controller curl through the installed tunnel, not the dedicated gateway account's SSH client or the Java application. Wrong SSH key/host identity, listener-conflict injection and Java no-direct-fallback are not tested. G3.2 and G3.5 remain open until their respective evidence is complete. Account preservation is not re-claimed by this script because it never accesses the application.

## Run

Open PowerShell7 as Administrator on the spare laptop, pull main once, then run:

```powershell
& '.\ops\windows\TestPaytmSecurityProbeBundle.ps1'
```

Normally allow1-2 minutes. Each curl is limited to6 seconds with a12-second process deadline; initial/final gateway waits are bounded to30 seconds each. Real progress and per-probe timing are captured in one `paytm-security-probes-*.json`. Expected status: `SECURITY_PROBES_PASSED_SSH_AND_HEALTH_TESTS_PENDING`. Share that file. If any check fails, the batch stops further requests and records the first failure plus final verification separately; do not reinstall or repeat recovery. No cleanup changes are necessary because this collector changes no gateway state. Existing E213 transport acceptance receipt is required in its original Review path; `-TransportReportPath` can select the same unedited bytes if moved.

## Local validation

55 assertions cover fixed destinations/proxy, TLS verification, timeout/unsupported rejection, missing metrics, false acceptance, wrong pin, ordered controls and stopping with evidence at each of six positions. Four controller workflows exercise success, subprocess timeout, incorrectly accepted pin and final installation drift with real temporary JSON reports and mocked privileged runtime APIs. These are local engineering checks; live spare validation is pending.
