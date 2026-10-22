# Post-manual-correction clock snapshot

## Current evidence and purpose

E164: the owner reports manually correcting Windows and seeing less than five seconds difference from the VPS. This is an owner observation, not measured application accuracy. The prior access diagnostic completed in8.208s: the elevated child could query/read W32Time but could not open SERVICE_START (error5). Its observed Administrators ACE lacks that right. Who/what configured those permissions is not established. **No permission reset or automatic-time repair is claimed.** The proposed VPS-backed application clock remains a discussion, not implemented or needed for this snapshot.

E165 prepares one read-only batch to compare Windows with the VPS and **the running main Java application**, not a separate fixture JVM. The existing authenticated `GET /api/v1/paper/account/overview` produces `observedAtUtc` using `Instant.now()` in `PaperAccountReadService.overview()`. Its indexed/bounded account/ledger queries are read-only and return no-store. Five such reads are performed, with no deployment/restart/migration/writer unlock or Paytm access.

## Measurement and limits

- Five pairs: authenticated pinned SSH VPS timestamp/NTP state, then authenticated localhost application GET. Before/after Windows UTC and monotonic elapsed time are captured around each request.
- Offset means **source minus Windows**. For source timestamp R observed during request [S,E], report conservative interval `[R-E-padding, R-S+padding]`, not just a midpoint. Padding is2ms plus the observed absolute difference between wall-clock and monotonic request duration. It covers timestamp quantization/observed local clock movement, **not the VPS's unknown absolute UTC error**.
- Require each request duration<=2s, observed wall/monotonic discrepancy<=100ms, ten samples, collection<=120s with <=100ms overall discrepancy, changing source timestamps, NTP=yes, and mutually compatible per-source offset intervals. All samples count: no best-case cherry picking. A network/SSH setup delay makes a sample uncertain, not proof that a clock is wrong.
- Aggregate conservative envelopes for VPS-minus-Windows and Java-minus-Windows, then their difference for Java-minus-VPS. All three must remain within +/-5s to satisfy this **diagnostic screening**, chosen to evaluate the owner's observation. It is NOT an allowed trading-time error or relaxation of the15-second quote rule. Comparisons are sequential and assume sufficiently stable clocks over this short window; sleep/restart/drift outside the window is unproven.
- Each native process/HTTP request has a15s timeout (Plink version5s; remote NTP query5s). Collection over120s is reported as a finding, not silently accepted. The complete workflow can take longer due to prerequisites and human key preparation/cleanup. Progress and native-process heartbeat remain visible. Timeout/partial results are retained, no automatic retry.
- NTP synchronized=yes is only a server observation, not proof of absolute accuracy. Successful relative screening does not enable quotes, approvals, trades, unattended custody or automatic synchronization. A separate operational/drift policy is still required; package maintenance remains pending.

Elapsed measurements use [.NET Stopwatch](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch). Stopwatch and wall clock are deliberately recorded separately; no timestamp returned by a remote host is used to set Windows time.

## Access and security boundaries

This is a **manual one-shot administrative diagnostic**, not an unattended gateway implementation. Pageant temporarily holds the owner's existing original administrator PPK; a committed **public-only selector** matches the key installed by `InstallVpsAdminKey.sh`. Plink0.83+ uses fixed host130.250.191.137, fixed RSA fingerprint, `marketbrain-admin`, batch mode, no connection sharing, no PTY/X11/agent forwarding, and fixed read-only remote commands. No sudo or password argument, no root login, no proxy/tunnel activation. Non-default PuTTY proxy/logging/forwarding/remote-command settings are rejected rather than changed. Authentication failure does not prompt for passwords or weaken the pin. An admin key remains powerful: load it only for the manual test and remove it afterward if added solely for this test; don't remove keys supporting unrelated sessions. Future unattended service must not reuse this unrestricted identity.

The existing Docker context must use a local Windows named pipe, with no DOCKER_HOST/DOCKER_CONTEXT override. Select exactly one running MarketBrain service matching this checkout and approved Compose/memory-review boundaries, localhost8080, PAPER mode and disabled Paytm credentials. Docker inspection is held privately; only container identity is reported. The existing read token is used in memory for localhost HTTP, never printed, written into the report or placed in process arguments. No redirects/system HTTP proxy. The report retains only clock values, bounds, findings, identity, timing and safety flags, not account data, full Docker environment or HTTP/SSH error bodies. Container identity/image/start and token must remain unchanged across the sample batch.

## Complete spare-laptop handoff

1. Keep jobs/tests idle and do not change clocks or let the laptop sleep during sampling. Existing application/Docker must be running. No PuTTY terminal, sudo, VPS paste, gateway PPK, or rebuild is needed.
2. Open **PowerShell7** as your normal Windows user (administrator elevation is not needed). Run:

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
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7 and run this block there.' }
& '.\ops\windows\TestPaytmClockSnapshot.ps1'
```

3. At the key prompt: open Pageant > View Keys > Add Key, select the **original administrator PPK used for marketbrain-admin**, and enter its passphrase in Pageant. **Do not select the separate marketbrain-paytm-gateway PPK.** If already loaded, do not add it again. Do not share either private key/passphrase.
4. Return to PowerShell and type `CLOCK-CHECK`. Five pairs run automatically. No START-TEST, STOP or SERVER_READY exchange.
5. At the end, review Pageant and remove only the admin key you added for this test (keep its encrypted PPK). Type `KEY-REVIEWED` after cleanup review. Share the single `paytm-clock-snapshot-...json` printed under `C:\MarketBrainData\Review`.

Possible results: `CLOCK_SNAPSHOT_WITHIN_SCREEN_RELEASE_PENDING`, `CLOCK_SNAPSHOT_CAPTURED_WITH_FINDINGS`, or `REVIEW_REQUIRED` on incomplete/failed collection or cleanup. Do not interpret the first as approval for trades. No repeat of the earlier VPS package refresh or Windows permission diagnosis is required.

## Verification

113 comparison/runner assertions include ten mocked whole workflows: successful screen, skew, SSH failure, timeout, stale nonce, HTTP failure, container restart, cancellation, key-cleanup omission and Docker failure.28 HTTP assertions verify fixed localhost/no-proxy/no-redirect access, private header handling, no-store, Java nanosecond timestamps, unsafe response rejection and sanitized failures. Bash syntax of the fixed remote command is checked without execution. No real VPS/Docker/application request ran on the development machine. Actual spare snapshot remains pending; no overall project completion percentage is increased.
