# Guarded application credential handoff

2026-10-15, E136/E137. This is the next deployment checkpoint, not permission to publish proposals or execute paper trades.

## Configuration guard correction

E138: the first spare run stopped before build/deployment after12.655s with `DEPLOY_UNREVIEWED_CONTAINER_SETTING`. NOLOGIN verification and the prerequisite account/storage reads passed. It did not restart the service or hand off the credential. The old report did not record which field caused rejection.

The guard incorrectly rejected optional field presence, including null/false defaults. This was reproduced in a failing regression. The correction accepts absent/null fields, Boolean false for privileged, and empty device/capability lists. It still rejects actual overrides and invalid types. Null command/entrypoint means inherit the image, but empty strings or arrays replace those defaults and remain prohibited ([Docker service specification](https://docs.docker.com/reference/compose-file/services/#entrypoint)).

Failures now name only the fixed setting, for example `DEPLOY_UNREVIEWED_CONTAINER_SETTING_COMMAND`, never its value.314 offline assertions across14 mocked runner scenarios pass, including serialized defaults and two new unsafe-setting full-runner checks. The236-test figure below is the earlier baseline. No new spare completion is claimed.

Pull the correction and run the script below once. This retry is appropriate because the reviewed report confirms deploymentAttempted=false and secretHandoffAttempted=false. Do not delete keys, regenerate passwords, repeat isolated verification, manually apply Compose or automatically retry a later unknown outcome.

## Why this step exists

The accepted isolated test proved memory custody and locked restart with a synthetic password. It did not prove that the actual application, existing Windows-protected credential, approval key and account configuration work together. This package verifies that integration while PostgreSQL still denies writer login.

Frozen acceptance: accepted source evidence; unchanged application settings and bind mounts except the approved review overlay; preserved approval key/read token; actual new service image; locked startup; credential unlock/idempotent replay; restart discards the credential; explicit re-unlock and final lock; independent NOLOGIN/no-writer-session checks; unchanged pristine INR100,000 account, revision0 and approval storage. D10/I30/V20 are complete locally; R20/A20 await the spare and owner. This is60% of this bounded package, not60% of the product.

## Prerequisites and effects

- Use PowerShell7 under the same Windows user who owns the CurrentUser DPAPI credential. Windows elevation does not substitute for that identity.
- Docker Desktop Linux engine and the current application must be running with exactly the accepted base plus paper-storage Compose stack. Repository changes, unexpected stack, configuration drift, altered mounts, missing reports or advanced account state stop the handoff.
- Keep the original accepted runtime report `paper-runtime-review-20261015-141726-1b8abb8c6f34.json` and installation report `paper-writer-install-20261012-151121-ca9707876fe9.json` in `C:\MarketBrainData\Review`. Their hashes are pinned. If moved, use the runner's explicit path parameters; do not edit report contents.
- Existing `writer.dpapi`, its custody lock and the separate approval encryption key are reused. No new password/key is generated. Read token comes privately from the existing container; it need not be memorized or pasted.
- Run while application jobs are idle. Type `DEPLOY_LOCKED_REVIEW` only after stopping other writer work. The script builds only the service, recreates it, then restarts it once to verify locked restart. Expect two service interruptions; the portal image is not rebuilt. Existing scheduled collection/alerts may resume normally after restart.
- Enter the PostgreSQL administrator username/password locally for bounded **read-only** identity, grants, credential-verifier and NOLOGIN checks. Do not send credentials in chat. Default PostgreSQL binaries are in `C:\Program Files\PostgreSQL\18\bin`; override `-PostgreSqlBin` if needed.
- No role mutation, proposal publication, order, reservation or fill is requested. The approved100s/15s/0.5%/quantity1/INR5,000 policy is installed, but the final credential state is LOCKED and the writer remains NOLOGIN.

## Run on the spare laptop

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 first.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -gt 0) {
    throw 'Repository check failed or local changes exist. Stop without discarding anything.'
}
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed. Do not deploy.' }
& '.\ops\windows\DeployPaperRuntimeReview.ps1'
```

Successful status: `APPLICATION_RUNTIME_HANDOFF_PASSED_LOCKED_NOLOGIN`.
Share the ONE `paper-runtime-application-*.json` file named by the script. It checkpoints progress, source/image identities, safe stage metadata, timings, account/storage readbacks and recovery state. It deliberately excludes raw Docker inspect/resolved configuration, secrets and native stderr bodies.

The build deadline is30minutes; readiness is bounded to30 requests with10-second request limits and5-second intervals. These are limits, not predicted runtime. Progress and elapsed stage evidence are recorded; no repeated model inference is involved.

## Failure and recovery

Do not automatically repeat deployment or run Compose manually after failure. The uniquely tagged image and report remain available, and the previous image ID is recorded; the script does not delete the old image or blindly roll back an uncertain deployment. Unknown unlock outcomes trigger an explicit lock attempt. An unverified final lock yields `RECOVERY_REQUIRED_DO_NOT_REDEPLOY`.

If the reviewed three-file service is running and only a lock/status check is needed:

```powershell
& '.\ops\windows\DeployPaperRuntimeReview.ps1' -LockOnly
```

This reads no protected password, performs no database probe/build/deploy, and is not a successful deployment receipt. It cannot repair a stopped application or an unexpected stack. Share its report before further action. A successful deployment deliberately does not support an automatic second normal deployment against the now-three-file stack.

## Verification and next gate

Local236 assertions cover12 mocked runner scenarios: success, configuration drift, NOLOGIN failure, failed build, uncertain deployment, health failure, wrong image, stale restart, lost unlock response, failed lock, account drift and lock-only recovery. These tests do not establish real Docker/Windows/DPAPI/application success. Prior781 Java tests remain a previous baseline; no Java code changed in E137.

After spare evidence is accepted, the next package addresses narrowly scoped publication/review permissions and a controlled private Telegram round trip with durable ACCEPT/REJECT/expiry receipts. No automatic order follows. Effective-access policy findings, simulated execution/fills/costs/P&L, numerical validation and the month-long paper pilot remain separate gates.

Implementation uses resolved configuration for private drift checks ([Docker Compose config](https://docs.docker.com/reference/cli/docker/compose/config/)) and a service-only recreate with no dependency startup, no build and no pull during the deployment step ([Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up/)). The preceding build is explicit; neither command output containing environment secrets is included in the report.
