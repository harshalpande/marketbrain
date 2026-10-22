# Paytm existing-container route probe

Update E155: owner run79e1a66d722c44c0ad9e8c3fcbf4b4d7 accepted7/7 in137.68s. [Acceptance](evidence/paytm-container-route-spare-20261022.json). Do not rerun this standalone probe. Proceed to [main application routing/restart](paytm-application-route.md). The original preparation/handoff below is retained as historical evidence.

2026-10-22, E154. Prerequisite E153: all nine Windows-to-VPS tunnel stages accepted in owner run8e80a1be628b47b9a66c893b235146aa (214.141seconds). No repeat of the accepted restrictions matrix is needed. This next package reuses its pinned tunnel and guarded VPS test window for a different question: **can Java in the existing application container reach the Windows loopback gateway?**

## Scope and why this comes before wiring

The running application uses an existing direct `PaytmMoneyHistoricalClient`. This package neither changes nor invokes it. The new `PaytmGatewayTransport`/`PaytmGatewayProbe` are dependency-free, not Spring beans, not scheduled and not exposed as HTTP endpoints. A temporary four-class JAR runs as a separate bounded JVM using the selected container's Java runtime/network. It cannot demonstrate that the already-running Spring application's HTTP client has been rewired. The report keeps `applicationContainerVerified=false` and `applicationProcessVerified=false`; success sets only `containerJvmRouteVerified=true`.

The explicit proxy selector has no DIRECT option and ignores the system selector. The only request available is credential-free HEAD to `https://developer.paytmmoney.com/`; no paths/tokens/headers can be supplied. Redirects are not followed; default certificate trust and HTTPS hostname checks remain enabled. Proxy connect timeout5seconds, request timeout15seconds; inside-container `timeout` kills the probe at25seconds, Windows process deadline35seconds. Each probe JVM has a64MiB heap cap. No API key, token, password, private PPK, broker order or database access is involved.

Oracle documents [explicit proxy configuration, connect timeout and redirect handling](https://docs.oracle.com/en/java/javase/21/docs/api/java.net.http/java/net/http/HttpClient.Builder.html). Docker Desktop has a [VM/host networking boundary](https://docs.docker.com/desktop/features/networking/); the host listener's reachability from `host.docker.internal` must be measured, not assumed. We do not rebind to0.0.0.0, change firewall rules, modify host mappings, set a system proxy, use host networking or enable direct fallback.

## What the runner does

1. Validates the accepted tunnel JSON; selects a local Windows named-pipe Docker context and one running Compose `marketbrain-service` belonging to this exact checkout. It never dumps container environment, secrets or full inspect/config output. Ambiguous selection stops.
2. Records container ID/image/start time and `/app/app.jar` hash. Compiles the two probe classes and local verifier with native JDK21 compatibility. Runs18 local proxy assertions. Packages only four probe classes, not the test verifier. Local Java-options overrides stop for review rather than being logged.
3. Creates one unique `/tmp/marketbrain-paytm-route-<runId>` directory in that container, copies the credential-free JAR and checks SHA256. No application replacement, rebuild, restart, package installation or Compose changes. Existing Upstox/Telegram and paper account settings are untouched.
4. Uses the same administrator confirmation, temporary Pageant gateway key and20-minute VPS proxy window as the accepted tunnel. It checks Windows TLS as a control, then the separate container JVM's TLS path.
5. Tests the container again after closing the owned SSH tunnel (must fail), after reconnect (must restore TLS), and after stopping the VPS proxy (must fail). This is route behavior, not proof of all container egress policy or main-process fail-closed wiring.
6. Removes only its temporary container JAR and empty directory and its uniquely generated Windows class directory. Checks the application container start time/image and JAR hash are unchanged. Saves one JSON with timings, class/source hashes, probe observations, subprocess results and server evidence. Cleanup failure prevents a pass. Application's ongoing data writes are not claimed to be frozen or compared.

If the first container request cannot reach the Windows listener, the result is REVIEW_REQUIRED. Finish the STOP/report/key-removal prompts, share the JSON and stop; do not expose the listener or repeat blindly. The failed probe is useful network evidence, not permission to modify the host firewall.

## Prerequisites and full handoff

- Existing MarketBrain service container running; Docker Desktop running on the spare. No restart requested. Native JDK21+ with `java.exe`, `javac.exe` and `jar.exe` in the same bin directory. Optional `-JavaBinDirectory` selects an existing JDK; no installation is automatic.
- Keep recovery access. In a fresh **administrator PuTTY session**, using the administrator PPK, run:

```bash
whoami
sudo whoami
sudo systemctl show marketbrain-paytm-gateway.service -p ActiveState --value
sudo ss -H -ltn 'sport = :18888'
sudo systemctl list-timers --all 'marketbrain-tunnel-stop-*' --no-pager
```

Require marketbrain-admin/root, inactive proxy, no18888 listener and no pending test timer. The transient stop-service warning from E153 did not invalidate confirmed proxy shutdown, but final timer state was not independently recorded; do this check before activation. Unexpected state: retain output and stop.

In **PowerShell on the spare**:

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Review local changes before updating.' }
$branch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Expected main branch.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
$accepted = 'C:\MarketBrainData\Review\paytm-tunnel-verification-20261022-130737-8e80a1be628b47b9a66c893b235146aa.json'
if (-not (Test-Path -LiteralPath $accepted -PathType Leaf)) { throw 'Locate the accepted tunnel report before proceeding.' }
& '.\ops\windows\TestPaytmContainerRoute.ps1' -TunnelEvidencePath $accepted
```

If discovery finds more than one application container, do not guess. Review its IDs and then use `-ApplicationContainerId` for the intended running service; the script still requires matching Compose service and checkout labels.

Interactive sequence:

1. PowerShell runs local/container preparation before VPS activation. At ADMIN-VERIFIED, confirm only after the fresh admin/sudo check.
2. Add the **separate gateway PPK** in Pageant; fingerprint `SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI`. Enter its passphrase privately, then type KEY-READY in PowerShell. Keep administrator/recovery keys separate.
3. PowerShell copies the generated VPS command and waits. In PuTTY **manually type** `sudo -v` so the clipboard is preserved; then paste the generated command and press Enter. At its prompt, type START-TEST within180seconds.
4. Copy the actual SERVER_READY output line from PuTTY into PowerShell and press Enter. It is a response to the Windows prompt, never a Linux command.
5. Let the route/recovery probes run. Answer PuTTY's STOP prompt only when PowerShell requests it.
6. Copy the complete BEGIN_SERVER_REPORT through END_SERVER_REPORT block. Return to PowerShell and press Enter only; it reads the clipboard.
7. Remove only the gateway key from Pageant when asked, retain the encrypted file, and confirm KEY-REMOVED. Allow temporary probe cleanup to finish. Share only the printed `paytm-container-route-...json`.

If PuTTY already returned to a normal shell, do not type START-TEST/STOP as shell commands; capture the finished report instead. Failure must still complete cleanup, not prompt another activation.

## Acceptance and remaining gates

Expected success: `CONTAINER_JVM_ROUTE_PASSED_APPLICATION_WIRING_PENDING`. All seven stages must pass, four Java observations must match TLS/refusal/TLS/refusal, selected container and app artifact must be unchanged, and cleanup confirmed. A503 response over verified TLS is still a transport pass and an API-readiness warning, not successful authentication.

Local evidence:18 native Java proxy assertions;14 targeted JUnit tests including the existing callback/login/history suites;20 PowerShell helper assertions;21 mocked workflow scenarios (16 accepted-runner regressions plus five container-mode scenarios); real native compilation, four-class packaging and local cleanup with mocked Docker operations. Local Docker API was unavailable; no real container/VPS execution is claimed. [Evidence](evidence/paytm-container-route-local-20261022.json).

Next after owner evidence: review any network blocker, then wire a dedicated guarded Paytm client into the actual Spring application, verify startup/restart and no direct fallback in that process. Fresh fixed-egress observation, unattended tunnel/key custody, OS maintenance, callback deployment, token lifecycle and quote entitlement remain separate gates. The main application's historical client is unchanged; this probe does not make it proxy-safe. No real trading is authorized. See the [integration sequence](paytm-integration-verification-plan.md).
