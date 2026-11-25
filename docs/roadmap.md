# Roadmap and completion dashboard

**25 November 2026 - publisher preflight configuration timeout diagnosed:** Automatically collected c22faf688482445382c225f3714a5ac3 stopped at Compose config after30.529s with zero stdout/stderr, before build/database inspection. Follow-up remote Compose/Docker version probes passed in0.342s/0.084s; original stall cause remains unestablished. Added separate bounded engine/plugin prerequisites,90s configuration allowance, explicit failure codes and sanitized stage collection.155 offline workflow assertions pass; catalog rerun pending. No application changes or database writes. G6 0%,24/30=80%. [Evidence](evidence/paytm-publisher-preflight-timeout-20261125.json).

**25 November 2026 - publisher installation rehearsal accepted; read-only catalog check prepared:** Automatically fetched paper-delivery-20261125-210423-8311e17efade.json: all47 checks passed (41 preparation,6 restart),188.204s;38 hashes match1392ec4. Disposable resources removed, no application database activity. Next GetPaperWriterPreflight.ps1 -Publisher inspects configured database catalog/role/function conflicts without changing permissions or restarting MarketBrain. Automatic collector projects publisher catalog reports with raw output/credentials excluded. Runtime catalog acceptance pending; G6 remains0%,24/30=80%. [Evidence](evidence/paytm-publisher-installer-accepted-20261125.json), [plan](paytm-telegram-review-plan.md).

**25 November 2026 - off-hours publisher installer rehearsal prepared:** The isolated delivery suite now uses the shared installation engine rather than fixture-only grants. It checks database identity/admin authority, existing-role/function collisions, schema trust, transactional rollback and disabled logins. Five added checks bring the suite to41 preparation plus6 restart checks (47 total). Real execution of this revision is pending on the spare laptop; no production installation or login activation. This test needs Docker only, not Paytm login or market hours. G6 remains0%, Paytm24/30=80%. [Plan](paytm-telegram-review-plan.md).

**25 November 2026 - restricted publisher database accepted; application wiring prepared:** Automatically fetched run2fcd6e606e0247f0bc017ed6bc2867b9 passed36 preparation plus6 restart checks in175.305s. All37 source hashes match7b216bf; disposable containers removed. Dedicated publisher connector and default-off process-memory runtime/control wiring added. No production publisher role, credential provisioning, endpoint or Telegram activation yet. Next: production role/custody deployment and bounded operator launcher. G6 remains0%, Paytm24/30=80%. [Plan](paytm-telegram-review-plan.md), [accepted evidence](evidence/paytm-restricted-publisher-accepted-20261125.json).

**25 November 2026 - restricted publisher interface prepared:** Candidate enqueue/lock/transition SQL and Java restricted delivery path implemented. Dedicated login is denied direct table/column writes; NOLOGIN helper owns fixed-search-path functions with PUBLIC execution revoked. 51 local Java tests and92 mocked PowerShell assertions pass. Disposable suite expanded to36 prepare plus6 restart checks; SQL runtime acceptance pending. No production role/function deployment or real messaging. G6 0%,24/30=80%. [Plan](paytm-telegram-review-plan.md), [local evidence](evidence/paytm-restricted-publisher-local-20261125.json).

**25 November 2026 - isolated publisher delivery database accepted:** Automatically collected run01d3d99010e54e1fa17283750e784293; all24 prepare and3 restart checks passed in426.675s. All30 source hashes match b60d185, disposable containers removed. Atomic three-proposal enqueue, later-insert rollback and token-preserving replay verified on PostgreSQL. Zero application DB/provider/Telegram/order/fill activity. Collector now supports these reports without manual upload. Next: restricted publisher deployment interface; real Telegram acceptance still pending. G6 0%,24/30=80%. [Evidence](evidence/paytm-delivery-batch-accepted-20261125.json).

**25 November 2026 - G6 bounded publisher prepared:** One authenticated reference quote builds three review-only proposals using the stored Telegram binding and account revision. Encrypted outbox enqueue is atomic for up to three distinct proposals; uncertain delivery remains non-retryable. 115 Java tests and 92 mocked PowerShell assertions passed. New publisher factory requires a separate non-owner publisher role and existing bound key; no role installed or runtime publisher activated. Next isolated database suite has 24 prepare plus 3 restart checks. G6 remains 0%, total24/30=80%. [Plan](paytm-telegram-review-plan.md), [local evidence](evidence/paytm-publisher-local-20261125.json).

**25 November 2026 - G6 callback wiring implemented locally:** Explicit PAYTM provider selection now connects the review callback to the identity-bound adapter and VPS clock. Requires the exact approved policy, PROCESS_MEMORY credentials and supervised controller; no Upstox credential requirement or clock/provider fallback. Existing defaults retained. Publisher/storage integration and combined spare Telegram acceptance remain pending; G6 0%, 24/30=80%. See [integration plan](paytm-telegram-review-plan.md).

**25 November 2026 - G6 Paytm review adapter prepared:** 133 targeted Java tests passed locally. New opt-in adapter re-resolves identity, uses the authenticated VPS-anchored clock and requires a fresh exact-paise quote under the separate 100-second Paytm policy. Existing Telegram wiring remains Upstox; no publisher or activation added. G6 runtime acceptance remains 0%, total 24/30=80%. [Combined integration plan](paytm-telegram-review-plan.md) and [local evidence](evidence/paytm-review-adapter-local-20261125.json).

**25 November 2026 - G5 supervised pilot baseline accepted:** Run100d613932d3441cb5219c75acfc4c58 returned3 identity-bound fresh RELIANCE quotes, ages1492/1250/1880ms; lock/gateway cleanup passed. Queue4c13f9ee-3e49-4a7c-8899-80f32f5f10a5 passed25 simulated HTTP cases using copied deployed client/assessor/Jackson in separate native JVM,15 deployed HTTP boundary checks and8 launcher fixtures;28.321s. Jar unchanged/temp cleanup verified. G5.3 accepted on combined actual fresh/stale runs plus isolated artifact and local controller integration evidence; malformed responses were NOT injected into live broker/running application. G5.5 accepted on source-bound fresh batch plus previous actual gateway-loss/lock/no-fallback evidence. RELIANCE pilot only, not all500; official unique-symbol bridge, no direct provider ISIN. G1/G2/G4/G5 100%, G3 80%, G6 0%;24/30=80%. Next G6 combined Telegram review-only integration. [Evidence](evidence/paytm-g5-pilot-accepted-20261125.json).

**24 November 2026 - holiday batch and pilot identity accepted:** G5.1 accepted for RELIANCE NSE EQ supervised pilot from authenticated identity-bound stale response plus official latest-published constituent/local ISIN unique-symbol bridge. Not all500/segments; Paytm master has no direct ISIN. Queue40a52616-fede-4a55-8847-ba81e54e0f05 passed15 deployed HTTP denials/locked-review checks and8 synthetic validator fixtures in7.891s. Local51 Java tests passed (simulated provider HTTP). No sessions or orders created by batch. G5 rises40% to60%; G1/G2/G4 100%, G3 80%, G6 0%, total22/30=73.3%. G5.3/G5.5 remain open; fresh bound quotes await next open market session. [Evidence](evidence/paytm-holiday-identity-accepted-20261124.json).

**21 November 2026 - mobile authorization requirement approved:** Telegram button opens official Paytm/CDSL authorization on the phone; no OTP via Telegram. Verify completion and revalidate the pending request; never replay expired approvals. Implement with G4 mobile/session work and the pre-live holdings-authorization gate, subject to verified provider handoff support. Next automated batch: seven no-credential application rejection probes; no broker calls, session creation or gateway changes. See [workflow](paytm-supervised-paper.md).

**21 November 2026 - quotes returned automatically:** [Queue evidence](evidence/paytm-quote-capture-20261121.json) accepts three Paytm NSE EQUITY samples for ID3456 at 266.35, correctly classified stale (about 19 hours); login/read and application/gateway cleanup passed, total 411.281s including owner login. No G5 checkpoint closes from stale samples alone. G1/G2 100%, G3 80%, G4 60%, G5/G6 0%; 17/30 (56.7%). [Mapping preparation](evidence/paytm-provider-mapping-preparation-20261121.json) verifies the official public master on the controller: ID3456 is TMPV, RELIANCE is ID2885. Next script resolves RELIANCE at runtime, captures three quotes and returns mapping/hash automatically. No rebuild, no orders, no Windows-clock repair. Market-hours freshness and local Nifty-universe identity remain open.

**Transport stability accepted, 2026-11-18:** [Recovery](evidence/gateway-transport-stability-accepted-20261118.json) passed 149 observations over 1811.422 seconds, same worker, zero reported transport failures, account preserved and application locked. Seven source hashes verified. [Automatic recheck](evidence/automation-transport-recheck-20261118.json) confirms running task, advancing heartbeat, TCP and both TLS probes; two runner/helper hashes verified. Root HTTP 503 remains broker-readiness warning. Health-account Windows time access and collector acceptance remain open; G3 80%, total 14/30 (46.7%).


**Recovery test sequencing defect confirmed, 2026-11-18:** [Recovery report](evidence/gateway-recovered-health-blocked-20261118.json) proves gateway TRANSPORT_READY and verified TLS, then application arm rejected TIMING_BLOCKED/HEALTH_UNCONFIRMED. No 30-minute soak completed. Cleanup preserved account/application lock; [automatic follow-up](evidence/gateway-health-stop-confirmed-20261118.json) confirms disabled task, exit 0 and STOPPED heartbeat. [Corrected transport-only resume](maintenance-automation.md#resume-after-application-health-block) prepared; no application health bypass. Runtime acceptance pending. G3 80%; 14/30 (46.7%).


**Current gateway recovery prepared, 2026-11-18:** [Bounded recovery](maintenance-automation.md#current-gateway-recovery-after-signing-acceptance) accepts only the current incident and verified signing receipt. Archive/recheck, one task start, 30-minute transport/application verification, failure cleanup and automatic sanitized result return. Runtime acceptance pending; no keys or installed gateway code replaced. G3 80%; overall 14/30 (46.7%).


**Gateway task state confirmed, 2026-11-18:** [Automatic retry](evidence/automation-task-state-20261118.json) confirms task enabled but idle (`Ready`), last result 1; saved HOST_AGENT_UNAVAILABLE remains. [Local signing step with automatic result collection](maintenance-automation.md#password-dependent-signing-with-automatic-result-return) prepared. Its Windows password stays on the spare laptop; runtime acceptance pending. No gateway reset. G3 remains 4/5 (80%), total 14/30 (46.7%).


**Gateway inspection accepted, 2026-11-18:** [Automated report](evidence/automation-gateway-blocked-20261118.json) contains the updated helper; both source hashes verified. Preserved HOST_AGENT_UNAVAILABLE latch and unchanged BLOCKED heartbeat from 16 November explain why recovery needs review. Current SSH-agent service Running is not per-account key proof; scheduled-task query timed out, so task state remains unknown. Elevated time sync recovered (error 0). No latch reset/restart; G3 remains 80%, 14/30 overall.

**Delayed automation result, 2026-11-18:** [Existing queued job completed](evidence/automation-delayed-old-helper-20261118.json) after network disruption; it was not cancelled. Returned helper is the previous F170 version, so supervisor inspection is still missing. At capture, gateway TCP failed and Windows reported stale time data (sync error 2). Runner updater now requires process/nonce/source-hash startup proof; transport status clears after reconnection. Runtime update acceptance pending; G3 80%, 14/30 overall.

**Gateway supervisor inspection prepared, 2026-11-18:** [Read-only diagnostic extension](maintenance-automation.md#resume-paytm-readiness-diagnostics) captures six fixed control/status/failure snapshots, named task result, SSH-agent state and second heartbeat. Secret/unknown fields excluded; no restart, latch reset or route rearm. Local helper update required; automatic result return already accepted. Actual supervisor cause remains pending. G3 unchanged at 80%, 14/30 overall.

**Paytm automated observation, 2026-11-18:** [Remote report](evidence/automation-paytm-observation-20261118.json) returned automatically; runner/helper hashes match reviewed source. Elevated operator W32Time queries passed. Loopback TCP 18889 failed; 2s proxy probe timed out and 8s probe failed to connect. Gateway supervisor cause is not yet established; inspect before restarting/resetting. Dedicated health-account time access remains unresolved. Collection succeeded, not Paytm readiness: G3 80%, 14/30 overall.

**Paytm diagnostics resume, 2026-11-18:** [Runner update](maintenance-automation.md#resume-paytm-readiness-diagnostics) prepared to return bounded Windows time-query evidence, local gateway listener/TCP state and 2s/8s proxy timing comparisons automatically. Read-only operator context, no credentials/elevation/threshold changes; it does not establish health-account readiness. One spare runner update required; no VPS change or re-pairing. Runtime diagnostic acceptance pending; G3 80%, 14/30 overall.

**Automation initial acceptance complete, 2026-11-18:** Diagnostic delivery/report return and real spare-laptop popup acknowledgment both passed (2/2 initial tests, 100% of this limited milestone). [Intervention evidence](evidence/automation-intervention-accepted-20261118.json) was retrieved directly by the agent; no manual upload. Existing Paytm catalogue, password/elevation handling, signed-out operation and lifecycle recovery remain pending. Paytm G3 unchanged at 80%; 14/30 overall.

**Automation diagnostic accepted, 2026-11-18:** Actual cross-machine job `0d38eb91-3c98-4e28-923e-b991f1281a13` succeeded and its report returned automatically to the development laptop. Runner source hash verified; Windows session 3, PowerShell 7.7, time service Running, orders disabled. [Evidence](evidence/automation-diagnostic-accepted-20261118.json). Intervention test pending; this does not validate background health-account access or close Paytm G3 (80%; 14/30 overall).

**Automation repair, 2026-11-18:** VPS journal shows relay.py permission denied and no port 18443 listener. Launcher umask 077 filters mkdir(0755) to 0700; installer now explicitly applies code-directory permissions, checks service-account access and verifies real TLS/HTTP readiness. [Existing-installation repair](maintenance-automation.md#repair-permission-denied-on-first-start) preserves pairing, certificate and queue. VPS acceptance pending; Paytm G3 remains 80%, overall 14/30 (46.7%).

**Current E294, 2026-11-18:** Collector diagnostics establish W32Time access denied (0x80070005) and three gateway curl connection timeouts; signing/clock/token passed and final application lock held. Fourteen source hashes match 12c9be2. User prioritized [automatic maintenance delivery and report return](maintenance-automation.md). Initial relay/runner and two-job acceptance prepared; VPS installation and cross-machine acceptance pending. Existing Paytm jobs/elevation and signed-out operation are not automated yet. G3 remains 80%; Paytm readiness 14/30 (46.7%).

**Historical E293, 2026-11-18:** First scheduled collector rejected all three rounds: Windows time/service/sync evidence and gateway TLS unconfirmed; one clock sample outside screening. Final health revocation passed, application locked and failed task disabled/retained. Fourteen source hashes match 06e77c6. Native error detail was omitted, so root cause is not established. [Bounded diagnostic rerun prepared](paytm-health-collector-batch.md#diagnostic-rerun-after-e293); no permission/firewall/threshold changes. G3 80%; Paytm readiness 14/30 (46.7%).

**Historical E292, 2026-11-18:** Restricted Java clock deployment accepted in 210.824 seconds: endpoint contracts before/after restart, preserved health token/account and locked writer/route. Eight script hashes plus revision match 2a60978. [Next: three-round scheduled collector integration](paytm-health-collector-batch.md), combining live time/transport observations, conditional health publication and final revocation. Durable installation and lifecycle acceptance remain pending. G3 80%; Paytm readiness 14/30 (46.7%).

**Historical E291, 2026-11-17:** Combined scheduled clock/token test accepted in 54.449 seconds: session 0, key signing, VPS clock, DPAPI decrypt, local authentication and task removal passed. Policy unchanged; eleven hashes match 950f392. [Next: restricted Java clock endpoint deployment](paytm-health-clock-deployment.md), preserving the existing health token. 27 Java tests and 17 deployment/rollback fixtures pass. Collector integration/lifecycle remain pending. G3 80%; Paytm readiness 14/30 (46.7%).

**Historical E290, 2026-11-17:** Health-token recovery accepted in 23.732 seconds. Exact-account encryption, fresh-process authentication, operator decryption denial, ciphertext cleanup and locked application passed; fourteen hashes match 9de6e9d. [Next: combined scheduled clock and token test](paytm-health-scheduled-token.md), 23 local checks passed. No token reinstall or batch-right changes. Collector integration and lifecycle acceptance remain pending. G3 80%; Paytm readiness 14/30 (46.7%).

**Historical E289, 2026-11-17:** Token-custody attempt stopped before worker launch because the source generator still referenced removed `$Token`; a fixture variable masked the defect. The retry correctly stopped on existing storage. Thirteen report source hashes match caad288. Fixed the generator, moved generation before installation writes, and prepared [receipt-bound recovery](paytm-health-token-custody.md#recovery-after-the-reviewed-pre-worker-failure). 43 checks pass, plus a PowerShell 7 reproduction of the original error and corrected generation with production imports. No token-custody acceptance yet. G3 80%; Paytm readiness 14/30 (46.7%).

**Historical E288, 2026-11-17:** Scheduled health signing and real VPS clock access accepted in 37.204 seconds: non-admin session 0, two signatures, nonce-bound synchronized clock reply, fresh-process signing and temporary task removal. Ten source hashes match 2a5d076; only health SID 1011 gained batch-logon allow, with denies unchanged. [Next: encrypted diagnostic health-token custody](paytm-health-token-custody.md). Collector and unattended lifecycle acceptance remain pending. G3 80%, Paytm readiness 14/30 (46.7%).

**Historical E287, 2026-11-17:** Health clock-key custody accepted in 38.967 seconds; import, targeted revocation/reimport, fresh-process signing and operator isolation passed; staged encrypted copy removed. Seven source hashes match ca49c93. [Next: scheduled signing and real clock access](paytm-health-scheduled-access.md), with batch-right precheck. Seventeen local tests passed. Collector/token and unattended lifecycle remain pending. G3 80%, overall 14/30 (46.7%).

**Historical E286, 2026-11-17:** Windows health account and storage accepted in 71.473 seconds; exact SID/non-admin token, protected write denial, work access and empty per-account agent passed. Three source hashes match fe6ae8d. [Next: clock-key custody batch](paytm-health-key-custody.md). Thirteen local checks plus 122 shared custody assertions passed. Scheduled access, token/collector and unattended acceptance remain pending. G3 80%, overall 14/30 (46.7%).

**Historical E285, 2026-11-16:** Actual clock SSH batch accepted in 63.971 seconds: pinned host, two valid nonce-bound NTP-synchronized replies, invalid-command rejection. All four source hashes match aeb2e12. [Next: Windows health account, protected storage and exact-account probe](paytm-health-account.md). Eight new tests plus 320 shared account assertions/26 mocked workflows pass locally. Key import and unattended worker remain pending. G3 80%, overall 14/30 (46.7%).

**Historical E284, 2026-11-16:** Clock login fingerprint passed but SSH could not load known_hosts under the spaced Windows profile path. Fixed SSH configuration-level path quoting. Real Windows ssh.exe loopback tests reproduce the old failure, pass the corrected authenticated command and reject a wrong host key. Eight existing clock checks and six controller checks pass. [Rerun only clock login](paytm-clock-login.md). No VPS changes. G3 remains 80%, overall 14/30 (46.7%).

**Historical E283, 2026-11-16:** Clock login stopped before authentication because Windows ssh-keyscan reported an unsupported KEX method. Removed the redundant scan; reuse the previously supplied RSA public key after verifying the unchanged accepted fingerprint. Six new controller/public-pin checks, eight clock checks and 122 shared custody assertions pass locally. [Rerun only clock login](paytm-clock-login.md); no VPS setup rerun. G3 remains 80%, overall 14/30 (46.7%).

**Historical E282, 2026-11-16:** VPS clock public-key authorization accepted (136.119 seconds overall, 0.078 seconds server operation). Four source hashes match d3816f3. Effective restrictions, reader integrity, public-key readability and locked password passed. No private transfer or SSH reload. [Next: actual clock SSH login and command denial](paytm-clock-login.md); eight local tests passed. Unattended custody remains pending. G3 80%; overall 14/30 (46.7%).

**Historical E281, 2026-11-16:** Dedicated encrypted Ed25519 clock key accepted from spare report (35.822 seconds); protected directory and identity checks passed; three source hashes match e3f76db. [Next: authorize reviewed public key](paytm-clock-key-authorization.md). Ten local tests passed. Private key remains on Windows; real SSH login and unattended custody not accepted yet. G3 80%, overall 14/30 (46.7%).


**Historical E280, 2026-11-15:** VPS keyless SSH policy accepted in 0.214 seconds: effective restrictions, other-account preservation and reload passed; keyless/password-locked retained. [Next: encrypted clock key preparation](paytm-clock-key-preparation.md). Five new local checks plus 122 existing custody assertions passed. No VPS authorization or worker installed by key preparation. G3 80%; 14/30 (46.7%).


**Historical E279, 2026-11-15:** Original clock-reader staging receipt recovered and accepted: password locked, keyless, fixed reader hash and allowed/denied command checks passed in 0.237 seconds. This is historical installation evidence; next installer rechecks live state. [Next: keyless SSH policy](paytm-clock-ssh-policy.md), with ten local tests. G3 remains 80%, 14/30 (46.7%); no unattended key/worker accepted yet.


**Historical E277, 2026-11-15:** Unattended preflight accepted in 40.810 seconds; 13 hashes match 00a79ea, proposed accounts/task absent, VPS Python/timedatectl present, account/writer/container preserved. [Next: keyless VPS clock-reader staging](paytm-clock-reader-stage.md). Eleven local tests passed; VPS execution pending. No background key/token/task installed. G3 80%, 14/30 (46.7%); explicitly announce G3 100% only after remaining acceptance.


**Historical E276, 2026-11-15:** Runtime lifecycle accepted in 133.478 seconds: fresh diagnostic arm, stale block/re-arm refusal, recovery requiring explicit arm and explicit revocation passed. Final revocation/account/writer/container/key cleanup passed; all 13 script hashes match 88df07b. [Next: unattended collector preflight](paytm-unattended-health.md). G3 still 80%; unattended identity, custody and lifecycle acceptance remain. 14/30 (46.7%), groups 100/100/80/0/0/0. Explicitly notify owner when G3 reaches 100%.


**Historical E274, 2026-11-15:** Three live publications accepted (1.962-3.253 seconds each); final revocation, writer lock, account/container/time-service preservation and key cleanup passed. All 12 script hashes match 34962b5. [Next: runtime health lifecycle](paytm-health-lifecycle.md), combining stale blocking, recovery without auto-arm and explicit revocation. Fifteen local fixtures pass. G3 remains 80%; groups 100/100/80/0/0/0 and 14/30 (46.7%). Explicitly notify the owner when accepted G3.5 evidence makes G3 reach 100%; do not infer completion from engineering tests.


**Historical E272, 2026-11-15:** Guarded health activation accepted in 195.378 seconds. All eight script hashes match 6baf042; HTTP negative/replay/expiry and restart checks passed, account preserved, writer and route locked, no rollback needed. [Next: live health publication](paytm-live-health-publication.md), three fresh rounds and final revocation in one run. Six mocked controller workflows passed locally. Healthy publication and unattended collection still await runtime evidence. G1/G2/G3/G4/G5/G6: 100/100/80/0/0/0%; 14/30 = 46.7%, no checkpoint increase.


**Historical E271, 2026-11-15:** Deployment preflight accepted in 9.244 seconds: 28/28 packaged migrations match source; Compose, account preservation, writer lock, unchanged container and cleanup passed. [Guarded service activation](paytm-health-activation.md) is now prepared, with 35 Java tests (including 39 guard assertions) and 11 mocked activation/rollback fixtures passing locally. Actual deployment and healthy/unattended publication remain pending. G1/G2/G3/G4/G5/G6: 100/100/80/0/0/0%; 14/30 = 46.7%, no checkpoint increase.


**Historical E270, 2026-11-15:** Spare Java-owned health transport batch accepted: 34 JUnit tests including 39 guard assertions, 110.305 seconds, cleanup successful; all 18 source hashes match 4568724. Running application unchanged. [Next: real deployment preflight](paytm-health-deployment-preflight.md): Compose preservation, packaged migrations, rollback image, account and writer lock. Nine local helper/controller fixtures passed; actual preflight pending. No credential or application activation yet. G3.5 open; 14/30 (46.7%), groups 100/100/80/0/0/0.

**Historical E269, 2026-11-15:** Spare publisher contract accepted: 15 checks in 0.201 seconds, zero network/credentials/application changes; all three source hashes match d22592c. [Next: Java-owned transport health verification](paytm-java-health-transport.md). Java now independently probes its fixed proxy before accepting healthy evidence; versioned publisher refuses older contracts. Local verification: 34 JUnit tests including 39 guard assertions, 16 publisher fixtures and four Docker-controller fixtures. Runtime deployment, protected credentials and unattended collection remain pending. G3.5 open; 14/30 (46.7%), groups 100/100/80/0/0/0.

**Historical E268, 2026-11-15:** Live collector rehearsal accepted: 3/3 rounds, 1.681-2.001 seconds per round, no findings; Windows synchronization and VPS NTP confirmed, fixed Windows proxy TLS verified (root HTTP 503 is not API readiness). All 8 source hashes match d2c5cf1. Container/settings unchanged and key cleanup confirmed. [Next: publisher contract verification](paytm-health-publisher.md). Fifteen local fixtures passed; no runtime publishing, Java transport authority, unattended reader or credential provisioning is claimed. G3.5 remains open: 14/30 (46.7%), groups 100/100/80/0/0/0.

**Historical E267, 2026-11-15:** Spare health-boundary Docker batch accepted: 30 JUnit tests including 39 guard assertions, 111.486 seconds, successful cleanup; all 18 source hashes match 5eae02e. Application unchanged. [Next: live health collector rehearsal](paytm-live-health-collector.md), combining fresh Windows status, pinned VPS and Java clock samples, and fixed-proxy TLS in three bounded rounds. Local 21-fixture verification passed. Publisher credentials, unattended collection and guarded main-application deployment remain pending. G3.5 stays open: 14/30 (46.7%), groups 100/100/80/0/0/0.

**Historical E266, 2026-11-15:** Spare isolated Docker route tests accepted: 20 JUnit tests including 39 guard assertions, 199.867 seconds, successful cleanup; all 15 source hashes match d7c63e2. Running application unchanged. [Next: authenticated health-input verification](paytm-health-bridge.md), 30 local JUnit tests plus four mocked controller workflows. Trusted Windows/VPS collector, credential provisioning and main-application deployment remain pending. G3.5 stays open: 14/30 (46.7%), groups 100/100/80/0/0/0.

**Historical E265, 2026-11-15:** Spare isolated Java guard passed39 checks in6.514s; compiler/JVM exit0, no network/settings/application changes. Five source hashes matchb06b1db. [Next: isolated Spring/diagnostic-route integration batch](paytm-timed-route-integration.md). Source route now uses guard and defaults locked without trusted health; do not deploy main application yet. Runtime health provider and deployment remain pending; G3.5 open,14/30 (46.7%), groups100/100/80/0/0/0.


**Historical E264, 2026-11-15:** Adaptive polling correction accepted in42.829s. Explicit config/resync success; three samples leap0/stratum5/error0, phase estimate26.328ms. Same time.windows.com server, flag0x9->0x8; Running/Automatic and ACL preserved, task removed, no rollback. Three source hashes matchf1618ec. [Next: isolated Java timing-guard verification](paytm-java-timing-guard.md);39 deterministic checks and full collector pass locally, production wiring pending. G3.5 open;14/30 (46.7%), groups100/100/80/0/0/0.


**Historical E263, 2026-11-15:** Health capture completed in75.187s; all nine peer offsets -10.468..+35.689ms, service Running/Automatic and configuration preserved. All three service observations remain unsynchronized; no health acceptance. Three source hashes match6b896f1. Owner authorized [controlled polling correction with rollback](paytm-polling-correction.md): same server,0x9 to0x8, one SYSTEM task, resync and three status samples. Local tests only; runtime pending. Groups100/100/80/0/0/0;14/30 (46.7%), unchanged.


**Historical E262, 2026-11-15:** Three-clock screen accepted in91.317s:10/10 usable observations, VPS NTP yes5/5, no findings, container unchanged and key cleanup confirmed. Bounds versus Windows: VPS -0.043..+0.964s; Java -0.086..+0.073s. Six source hashes matchc7d8f18. Prior16-17s mismatch absent in this observation; durable Windows synchronization remains unproven. [Next: bounded read-only clock-health batch](paytm-clock-health.md). G3.5 stays open;14/30 (46.7%), groups100/100/80/0/0/0.


**Historical E261, 2026-11-15:** Read-only source review captured in6.243s. Three stripchart offsets +6.275/+14.154/+18.705ms; events37/35 record valid data/synchronization. Current status still leap3/stratum0/error1: conflicting evidence, not synchronization acceptance. Both source hashes matcha7405e4; service remains Running/Automatic and configuration unchanged. [Next: independent three-clock comparison](paytm-clock-after-source-review.md), no repair rerun or peer changes. G3.5 remains open; groups100/100/80/0/0/0;14/30 (46.7%).


**Historical E260, 2026-11-15:** Service repair confirmed in12.837s: Running/Automatic, ACL and peer preserved, task removed. Synchronization NOT accepted: w32tm returned zero but explicitly reported no time data; leap3/stratum0/error1. Three source hashes match852c212. False-positive resync classification corrected; [read-only source review next](paytm-time-source-review.md), do not rerun repair. G3.5 blocked; groups100/100/80/0/0/0,14/30 (46.7%), unchanged.


**Historical E259, 2026-11-15:** Repair stopped before mutation: fresh PS5.1 worker lacked the ServiceController assembly; zero repair commands, no resync, temporary task removed (11.185s). All three source hashes match cffa46a. Explicit assembly loading fixes the reproduced defect; real read-only fresh-process tests pass in PS5.1 and PS7, plus 47 helper assertions/four controller fixtures. [Retry the corrected repair](paytm-time-service-repair.md); clock alignment remains pending. Groups 100/100/80/0/0/0;14/30 (46.7%), unchanged.


**Historical E258, 2026-11-15:** Windows Time access diagnosis captured in 7.911s: stopped/manual service; elevated administrator lacks SERVICE_START, SYSTEM has the required rights. Six source hashes match 2592b23. [Next: one-time SYSTEM repair preserving service ACL and existing time peers](paytm-time-service-repair.md). Offline verification: 47 assertions and four controller workflows; actual repair and fresh clock comparison pending. G3.5 remains blocked; groups 100/100/80/0/0/0, 14/30 (46.7%), unchanged.


**Historical E257, 2026-11-15:** Clock collection completed with findings, not acceptance: VPS16.188-17.325s ahead of Windows; Java relative to Windows -0.030 to+0.033s. All10 samples collected, VPS NTP yes5/5, six source hashes matchca02d27 CRLF, unchanged container and key cleanup confirmed. [Next: fresh read-only Windows Time access diagnosis](paytm-clock-drift-followup.md). Historical SERVICE_START denial is not assumed current. G3.5 blocked;14/30 (46.7%), unchanged.

**Historical E256, 2026-11-15:** Actual runtime listener latch/recovery accepted in33.485s. Nine source hashes match1c1b99c CRLF; exact worker conflict persisted10.868s, verified marker archive, one start, fresh recovered worker. Java absent-tunnel failure and subsequent lock passed; account/container/final locks preserved. G3.2 complete: groups100/100/80/0/0/0;14/30 (46.7%). [Next: fresh read-only three-clock snapshot](paytm-clock-refresh.md); G3.5 remains open.

**Historical E255, 2026-11-15:** Listener/policy report accepted:15 checks in6.439s,10 source hashes match9eb99f5 CRLF, same advancing worker. Real duplicate bind refused with AddressAlreadyInUse; isolated policy results remain separate. [Next: actual runtime listener latch, absent-tunnel Java failure and owned recovery](paytm-runtime-latch.md).23 helper assertions and six controller workflows passed locally. G3.2/G3.5 pending;13/30 (43.3%).

**Historical E254, 2026-11-15:** [Listener and installed-policy batch prepared](paytm-listener-policy-probes.md). Real owned-listener/duplicate-bind checks plus isolated execution of hash-verified installed latch/deadline functions, in one report without restarting the gateway. Local15 checks/eight assertions/nine controller workflows pass;55 existing probe assertions pass. Runtime supervisor latching and clock/application enforcement are not established. Groups100/100/60/0/0/0;13/30 (43.3%), unchanged.

**Historical E253, 2026-11-15:** Disposable SSH rejection batch accepted in8.257s. Incorrect host identity and unregistered key both rejected; disposable files removed. All ten source hashes match8f40d5e CRLF; same advancing gateway, attempts2->2, failures0->0. No installed credentials, application access or configuration changes. Next: installed listener-conflict/failure-latching coverage, then clock/health/application no-fallback. G3.2/G3.5 remain open;13/30 (43.3%). No SSH test rerun needed.

**Historical E252, 2026-11-15:** Actual TLS/proxy rejection batch accepted in8.53s: all six checks pass, nine source hashes match029068f CRLF, same advancing gateway before/after. Wrong TLS pin exit90; host/port/plaintext403; allowed root503 is transport-only. [Next: two disposable SSH rejection probes](paytm-ssh-negative-probes.md).31 SSH assertions, real local key generation and six controller workflows pass. G3.2/G3.5 remain pending;13/30 (43.3%).

**Historical E251, 2026-11-15:** Credential-free security probe batch prepared: allowed HTTPS controls before/after, actual wrong TLS pin, forbidden host/port and plaintext denials through the installed gateway. Local verification:55 assertions and4 controller workflows passed. [Run the short security batch](paytm-security-probes.md). Spare evidence pending; G3.2/G3.5 remain open. Groups100/100/60/0/0/0;13/30 (43.3%), unchanged.

**Historical E250, 2026-11-15:** Sign-out and full shutdown/startup accepted. All eight source hashes match 641c77c CRLF; same background worker across changed logon, new worker after new Windows boot, all three route/account/final-lock proofs pass. Transient failures recovered automatically (AfterLogoff: 4 attempts/3 failures; new boot: 2 attempts/1 failure); uninterrupted availability is not established. G3.4 complete. Groups 100/100/60/0/0/0; 13/30 (43.3%). Next: G3.2 security-negative cases and G3.5 clock/health/no-direct-fallback review. No session test rerun needed.

**Historical E249, 2026-11-14:** Sustained gateway stability accepted: 1803.187 seconds, 144 observations, same worker and SSH child, one connection attempt and zero recorded transport failures. Both application routes, unchanged INR100000 paper account and final locks passed. [Next: fresh sign-out and full shutdown/startup verification](paytm-gateway-session.md). Groups 100/100/40/0/0/0; 12/30 (40%), unchanged until G3.4 passes. Broker authentication and quotes remain untested.

**Historical E248, 2026-11-14:** Diagnostic collection accepted:303.812s,55 ready samples, zero sampled outages/recorded transport failures; final stop, account and locks passed. Report22,202 bytes. [Next: existing30-minute stability check after guarded start](paytm-tls-stability.md), no installed-code change. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E247, 2026-11-14:** Current-state report confirms worker STOPPED, disabled task and absent process after overflow. Saved counters:one connection attempt, zero transport failures; final HTTPS probe621ms. [Next: guarded five-minute capture rerun](paytm-capture-resume.md), corrected bounded report storage, no installed-code replacement. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E246, 2026-11-14:** Diagnostic collector exceeded64KiB after43 ready samples; final cleanup unverified from console. Reproduced and fixed with bounded samples and fallback cleanup receipt. [Next: read-only checkpoint/current-state capture](paytm-capture-size-recovery.md); do not rerun stale recovery. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E245, 2026-11-14:** Recovery again failed: HTTPS timeouts after CONNECT200, while BACKOFF heartbeats advanced. Failure cleanup/account/locks passed. [Next: five-minute TLS phase diagnostic with mandatory stop](paytm-tls-phase-diagnostic.md). Misleading readiness timeout corrected; root cause unproven. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E244, 2026-11-13:** SSH incident evidence accepted:196 journal rows, one gateway key login, no classified throttling entries. Exact connection match and cause unproven. [Next: one controlled recovery without code replacement](paytm-incident-recovery.md), then existing30-minute stability/application/account checks. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E243, 2026-11-13:** Diagnostic recovery reached initial TLS, then failed at reconnect TCP timeout. Cleanup stopped the worker; account and final locks preserved. [Next: read-only SSH incident correlation](paytm-ssh-incident.md), no restart or sign-out. VPS accepted a gateway key, but exact connection matching and cause remain unproven. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E242, 2026-11-13:** AfterLogoff failed with HOST_AGENT_UNAVAILABLE; TLS instability also existed before sign-out. [Next: agent-query/native-phase diagnostic recovery](paytm-agent-recovery.md). Do not proceed to shutdown or reuse the old session phase. Cause unproven; groups 100/100/40/0/0/0, 12/30 (40%).

**Historical E241, 2026-11-13:** Windows diagnostic recovery accepted: 1805.703s soak, 129 observations, zero reconnects/failures, both application routes and final locks/account passed. [Next: fresh sign-out/full-shutdown workflow](paytm-gateway-session.md). No rebuild or recovery rerun. Groups 100/100/40/0/0/0; 12/30 (40%), G3.4 pending.

**Historical E240, 2026-11-13:** VPS direct/proxy comparison passed all 60 TLS requests in 298s; all HTTP 503, not broker readiness. [Next: Windows recovery with bounded TLS diagnostics](paytm-agent-recovery.md), one start and unchanged 30-minute observation/locks. Original interruption unexplained. Groups 100/100/40/0/0/0; 12/30 (40%).

**Historical E237, 2026-11-13:** Account signing accepted: expected key and two signatures passed, temporary task removed, production state preserved. [Next: archived gateway recovery and 30-minute observation](paytm-agent-recovery.md). Original failure cause remains unknown. Groups100/100/40/0/0/0;12/30 (40%), unchanged.

**Historical E236, 2026-11-06:** Agent diagnostic accepted in **4.957s**; four source hashes match `f8a3061` CRLF. ssh-agent was Running/automatic with zero exit codes; all six event queries were empty, and the checkpoint was unchanged. The production worker is stopped; historical cause remains unknown. [Next: dedicated-account local signing](paytm-agent-signing.md), one temporary task and one JSON, preserving production state. Full shutdown remains paused. Groups **100/100/40/0/0/0, 12/30 (40%)**, unchanged.

**Historical E235, 2026-11-06:** Session baseline passed; AfterLogoff stopped after **49.36s** with `HOST_AGENT_UNAVAILABLE` in the background worker. All eight source hashes match `7c9e321` with CRLF. The report does not distinguish an SSH-agent query timeout from a nonzero exit. [Next: read-only service/event evidence](paytm-agent-failure.md), one JSON; preserve the checkpoint and pause sign-out/shutdown testing. Current gateway health is blocked. Groups remain **100/100/40/0/0/0, 12/30 (40%)**, with no new checkpoint accepted.

**Historical E234, 2026-11-05:** Native recovery and 30-minute observation accepted: **1847.099s total, 1809.708s observation, 129 observations**, all six source hashes match `60cc983`. Eight-file archive verified, one start, same worker/SSH child, zero transport failures/reconnects; both application route checks, final application/writer locks and unchanged INR100000 account pass. Original historical native operation remains unknown. [Next: baseline, actual Windows sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases. A missing application-checkpoint callback was caught locally and corrected before handoff. No recovery/network repeat. Groups remain **100/100/40/0/0/0, 12/30 (40%)**; G3.4 closes only after its final runtime report passes.

**Historical E233, 2026-11-05:** Corrected native evidence completed in **6.801s**, four sources match `07242e7`. Both executable signatures and metadata are complete; three installed hashes match and selected policy queries are empty. The gateway is still stopped; original native operation remains unproven. [Next: archived native-process correction, one restart and 30-minute observation](paytm-native-recovery.md). Cleanup preserves the first failure and records native operations; a denied stop is ignored only after confirmed child exit. 398 local assertions pass; actual gateway-account recovery and soak remain pending. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**.

**Historical E232, 2026-11-05:** Native capture completed in **13.116s**, four sources match `d372adc`, and all three installed helper hashes match their manifest. Three selected event queries returned no matches; administrator curl version succeeded. Both executable metadata rows failed with `CommandNotFoundException`, so the success label did not establish complete collection. [Corrected read-only collection](paytm-native-failure.md) explicitly loads inbox Windows modules, records the metadata stage and rejects missing fields; 117 local assertions include actual PS7-to-PS5 metadata checks with discovery disabled. Worker remains stopped; original native error5 cause unconfirmed. Groups **100/100/40/0/0/0, 12/30 (40%), no increase**; session testing remains on hold.

**Historical E231, 2026-11-05:** Worker inspection completed in **3.16s**; all five source hashes match `2ce584c`. The E228 worker later stopped at a native Windows **Access denied (5)** exception during the observation loop, after 1387.3s recorded uptime. Source line77 points to the curl health-check wrapper; the exact denied native operation is not captured. Task enabled/Ready/result1, process absent, no advancing heartbeat, no session checkpoint. [Next: bounded native/event evidence](paytm-native-failure.md), one read-only report; no marker reset, ACL change or gateway restart. Session testing stays on hold. Accepted groups remain **100/100/40/0/0/0, 12/30 (40%), no increase**; current health is blocked.


**Historical E230, 2026-11-05:** The session baseline stopped after **0.383s** at `STARTUP_WORKER_FAILURE_PRESENT`; all seven source hashes match `dc1ea47`. A saved worker-failure marker blocks the next stage, but the report omitted its contents, so the cause and current worker health are unknown. No session baseline, task/power change or application/account check was completed. [Next: read-only worker inspection](paytm-gateway-session.md#current-handoff-read-the-saved-worker-failure), one JSON; do not sign out, shut down, clear markers or retry the baseline. The collector now includes bounded worker diagnostics automatically for worker failures. E228 network acceptance remains valid at its recorded scope; groups **100/100/40/0/0/0, 12/30 (40%), no increase**. Account/lock flags in this failed run mean unverified, not a proven balance change.


**Historical E228, 2026-11-05:** Network interruption/recovery accepted in **84.761s**; all 11 source hashes match `5ba324a`. Actual replacement SSH denial produced advancing BACKOFF; the same worker reconnected on attempt 3 (23s recorded outage). Both temporary rules/tasks were removed; 3/3 application route checks, no automatic rearm, final application/writer locks and unchanged INR100000 account passed. **G3.1 closes: groups 100/100/40/0/0/0, 12/30 checkpoints (40%, +3.33 percentage points).** This measures the bounded Paytm plan at capture, not whole-project completion or current uptime. Do not rerun recovery/network. [Next: sign-out and full shutdown/startup](paytm-gateway-session.md), one report across three phases; runtime acceptance remains pending. Login, quotes, remaining security/health checks and Telegram review stay open. Root HTTP503 remains transport-only evidence.

**Historical E227, 2026-11-05:** The 5.083s run matched the reviewed receipt hash, then rejected its contents. Root cause reproduced: the checkpoint writer's unqualified path resolved to the helper's input Path and overwrote that receipt. Script-scoped output/timer/report binding fixes this; regression now combines the real reader, validator and writer. [Next: same exact-state recovery using the original byte-pinned repository snapshot](paytm-gateway-network.md), with no manual file restoration. All 11 sources match ea69e3e; no recovery/firewall mutation occurred, saved failure is unchanged, account preserved and application/writer locked. Gateway remains blocked/stopped/disabled. Groups **100/100/20/0/0/0, 11/30 (36.7%), no increase**.

**Historical E222/E223, 2026-11-04:** Cancellation and recovery accepted in 51.253s; all 11 source hashes match bdc162a. Both processes exited and the listener disappeared in 1.529s. A 10.785s quiet interval, fresh healthy worker, 3/3 application checks, unchanged INR 100000 account and final application/writer locks passed. **G3.3 closes: groups 100/100/20/0/0/0, 11/30 checkpoints (36.7%, +3.33 percentage points).** This measures accepted evidence at capture, not continuous health or whole-project completion. Next: [one guarded network-interruption/recovery batch](paytm-gateway-network.md), with a disabled-rule cleanup rehearsal before the real outage. Engineering is prepared; spare acceptance is pending. Do not rerun cancellation/recovery. HTTP 503 remains transport-only evidence; login, quotes and orders remain pending. The original overwritten worker failure remains unknown.

**Historical E221, 2026-11-04:** Recovery archived the evidence and updated the runner/manifest successfully, but the controller read the first heartbeat too early (FileNotFoundException,20.68s). Eleven source hashes verified. A later sample shows a fresh CONNECTING worker with identity/signing passed; TLS/cancellation not established. Cleanup verified STOP/task disable, unchanged INR100000 account and locked application. Bounded startup waiting is corrected; [resume the completed recovery](paytm-gateway-cancellation.md#current-handoff-resume-the-completed-recovery) verifies existing archives/installation and starts the exact task once before cancellation. No reinstall or marker reset. Accepted groups100/100/0/0/0/0,10/30 (33.3%); current gateway deliberately stopped. Earlier recovery command is superseded.

**Historical E220, 2026-11-04:** Inspection succeeded in3.802s; all eight source hashes verified against c1718eb. Worker exited; task result1; the failure latch says TRANSPORT_PREVIOUS_FAILURE_REVIEW_REQUIRED. The old runner overwrote the original cause during a later launch, so that cause remains unknown. First-cause preservation is corrected; [one reviewed recovery plus cancellation batch](paytm-gateway-cancellation.md#current-handoff-recover-once-and-test-cancellation) archives exact evidence, patches only the runner/manifest, makes one fresh start and continues only if healthy. Runtime recovery remains pending. Accepted groups **100/100/0/0/0/0**,10/30 checkpoints (33.3%); current gateway health blocked. This supersedes the earlier InspectOnly handoff.

**Historical E219, 2026-11-04:** The read-only inspection failed after4.489s because the diagnostic reader accessed optional JSON properties under production StrictMode. Reproduced with actual imports and corrected throughout the reader; eight source hashes verified. [Pull and retry InspectOnly](paytm-gateway-cancellation.md#current-handoff-inspect-the-saved-worker-failure), one JSON. Original worker failure/current health remain unknown. Accepted groups **100/100/0/0/0/0** unchanged; cancellation remains on hold.

**Historical E218, 2026-11-04:** Cancellation stopped before changes after3.145s: a saved worker failure marker exists, but its contents were omitted. Seven source hashes verified. Underlying cause/current worker health are unknown. [Next: read-only worker failure capture](paytm-gateway-cancellation.md#current-handoff-inspect-the-saved-worker-failure) using `-InspectOnly`, one JSON; do not reset markers or rerun cancellation yet. Accepted groups **100/100/0/0/0/0** remain unchanged; G3 is blocked pending diagnosis.

**Historical E216/E217, 2026-11-03:** Windows restart accepted in14.623s: new background worker, application TLS route, preserved INR100000 account and final locked application/writer. Five source hashes verified. G2.4 closes; groups **100/100/0/0/0/0**,10/30 accepted checkpoints (33.33% of this bounded plan). [Next: task cancellation and application recovery](paytm-gateway-cancellation.md), one combined batch with orphan/listener cleanup, failure locking and explicit restart without automatic rearm. No reinstall, reboot, key import or VPS change. Remaining G3 and Paytm login/quotes still pending; HTTP503 is transport-only evidence.

**Historical E215, 2026-11-03:** The after-restart report shows a new session-0 worker running with transport ready. Verification stopped after 24.798s because an unsupported 15-second task/process timestamp comparison rejected a 31.352325-second difference. Five source hashes match the reviewed CRLF checkout. The corrected collector validates both timestamps within the new boot window and records their difference; 94 local assertions pass. [Retry After only](paytm-gateway-windows-restart.md#retry-this-interrupted-after-phase): preserve the baseline, no reboot or reinstall. Application/account checks were not reached. Groups remain **100/80/0/0/0/0**, 9/30 accepted checkpoints; full startup acceptance is pending.

**Historical E213/E214, 2026-11-03:** Managed transport accepted in64.115s: all4 application-route checks, duplicate start, deliberate disable, child reconnect and persistent STOP pass; account remains INR100000 and application/writer finish locked. Seven source hashes verified. G2.5 closes: groups **100/80/0/0/0/0**,9/30 checkpoints. [Next: before/after Windows restart verification](paytm-gateway-windows-restart.md),66 local assertions, one report. No installer/key/VPS rerun. Actual Windows startup, remaining G3 recovery/security cases, login and quotes remain pending; HTTP503 is TLS-route evidence only.

**Historical E212, 2026-11-03:** [Managed transport retry](paytm-managed-windows-transport.md) corrects application discovery. Run6fa5d4c881224b6d8dd61a775123fb2b stopped after7.907s before backup/upgrade; the existing supervisor remained LOCKED. Seven source hashes match378a53b. The old report cannot distinguish no running container from multiple candidates. New lookup matches the exact Compose workspace and records stopped/paused/restarting/duplicate states without secrets or automatic restart.25 assertions/11 discovery scenarios and10 deployment regressions pass. Confirm the existing app is running, pull and retry the same batch. Groups100/60/0/0/0/0 unchanged; no VPS/account/key rerun.

**Historical E211, 2026-11-03:** [Managed Windows transport and application-route batch](paytm-managed-windows-transport.md) is implemented and locally verified: 230 assertions covering adapters, native Windows processes/listeners/curl, restricted-policy bootstrap, upgrade workflow and regressions. Reuses the accepted account, task, agent key, VPS and existing application. One spare run combines connection, TLS/denials, duplicate start, disable, child recovery, persistent STOP and route/account checks. No rebuild or VPS reinstall. Spare acceptance and actual boot/logoff remain pending; groups **100/60/0/0/0/0** are unchanged. Earlier handoffs below are historical.

**Historical E210, 2026-11-02:** [Managed VPS lifecycle accepted](evidence/paytm-managed-proxy-accepted-20261102.json). Original valid report proves a10-second pass;46.141-second recovery confirms running/boot-enabled loopback proxy, matching PID/marker and no guard timers. Earlier pasted JSON was corrupted; installation was not repeated. No VPS rerun or further recovery is needed. Next is Windows supervisor transport and effective application-route integration. This VPS substage is100%; full groups remain100/60/0/0/0/0 until their remaining checkpoint requirements pass. Earlier install/recovery instructions below are historical.

**Historical E209, 2026-11-02:** Managed-proxy collection failed at JSON decoding after104.128s; VPS outcome is unconfirmed because the original report was not retained. Windows was LOCKED before the remote step. **Do not rerun installation.** [Recover the saved VPS report and current state](paytm-managed-report-recovery.md) without service changes. Collector now preserves malformed report evidence. Accepted groups remain100/60/0/0/0/0; earlier installation handoffs are on hold.

**Historical E207/E208, 2026-11-02:** Locked supervisor recovery accepted in **36.582 seconds**: background signing, same-process duplicate start, persistent STOP and fresh locked restart passed; ten source hashes verified. Do not rerun recovery or import keys. Next: [managed VPS proxy lifecycle](paytm-managed-proxy.md), combining crash recovery, durable disable, TLS and denial checks while Windows stays locked. Runtime installation is pending; accepted groups remain **100/60/0/0/0/0**. Production Windows transport and actual boot/logoff remain open. Earlier handoffs below are historical.

**Historical E206, 2026-11-02:** [Recover the retained supervisor task](paytm-supervisor-installation.md). Installation prerequisites and registration passed, but task exit1 preceded any heartbeat. File-based helper loading fails under Restricted policy in local reproduction; the original report omitted its exact startup exception. Corrected inline loading, early diagnostics and scoped runner-only recovery are ready;171 local assertions pass. Do not reinstall, recreate the account or reimport keys. Accepted groups remain **100/60/0/0/0/0**.

**Historical E205, 2026-11-02:** [Locked supervisor/startup installation](paytm-supervisor-installation.md) is ready for the spare laptop. One batch checks actual background heartbeat, duplicate start, persistent STOP and locked restart. Local 48 host checks plus 79 gateway regressions pass. Production transport adapters, VPS lifecycle and cold-boot acceptance remain pending. E204 signing remains accepted; do not rerun repair or key import. Accepted groups remain **100/60/0/0/0/0**.

**Historical E204, 2026-11-02:** [Batch-logon correction and background signing accepted](evidence/paytm-scheduled-signing-accepted-20261102.json). Total11.675s/worker1.979s; exact non-admin session0,2/2 signatures, task exit0 and temporary task removed. Other policy assignments preserved; no key/password/network/order changes. **Do not rerun repair.** Next: production supervisor and scheduled startup. This G2.4 prerequisite is complete; full group checkpoints remain **100/60/0/0/0/0**.

**Historical E195, 2026-10-26:** G2.3 [controlled custody and pinned-authentication implementation](paytm-gateway-key-custody.md) locally verified after owner-confirmed encrypted export. One batch includes protected staging, private console, targeted revoke/reload, host-pin negative/positive and new-process signing. Actual spare acceptance pending;100/40/0/0/0/0 unchanged. No account recovery rerun. Subsequent supervisor/task, managed lifecycle and true installed-system/reboot recovery remain gates.

**Historical E194, 2026-10-26:** real gateway account recovery/probe accepted, G2.2 closed: **G1=100%, G2=40%, G3–G6=0%; G2 delta +20 points**. Old storage preserved and service unchanged. [Next G2.3: key custody and pinned restricted authentication](paytm-gateway-key-custody.md), format confirmation pending. No more Apply/Recover/Verify/account inventory runs. Earlier next-step instructions below are historical. This is Paytm readiness checkpoint credit, not whole-platform completion.

2026-10-26 E192/E193: residual state reviewed; [controlled Recover](paytm-gateway-account.md) prepared and locally tested to preserve old storage, recreate a restricted identity and verify it while preserving the shared agent. Actual spare recovery still gates G2.2. Accepted percentages100/20/0/0/0/0 unchanged; success plus review would move G2 to40%. Earlier next-step statements below are historical, not commands for the deleted-account state.

2026-10-26 E189/E190: Windows account/storage/agent installation and postchecks succeeded, but exact-account probe launch failed before execution. [Corrected Verify-only handoff](paytm-gateway-account.md) preserves all installed state and existing password. Native command-length/transport regression added;236 assertions/17 mocked workflows passed locally. **G1=100%, G2=20%, G3/G4/G5/G6=0%; delta0.** Six completed install stages are tangible progress, not yet G2.2 acceptance; real probe success would yield40%.

2026-10-24 E187/E188: account creation remains pending after a pre-change password-confirmation stop, not an administrator/service failure. [Corrected Apply handoff](paytm-gateway-account.md),199 local assertions/16 mocked workflows; no cleanup needed for this report. **G1=100%, G2=20%, G3/G4/G5/G6=0%, delta0.** Next successful reviewed account evidence targets G2.2/40%; no guaranteed execution count or broader readiness credit.

2026-10-23 E185/E186: [fixed group-percentage baseline](paytm-readiness-progress.md) introduced at owner's request: five equal accepted checkpoints per group, evidence-based rather than estimated effort. **G1 100%; G2 20%; G3/G4/G5/G6 0%.** Spare foundation accepted; [Windows account/agent provisioning](paytm-gateway-account.md) next. Successful reviewed runtime evidence would close G2.2 and yield40%, not complete group2. One fully completed group remains; prior route work is preserved as prerequisite evidence. No maintenance/foundation repeat.

2026-10-23 E183/E184: **maintenance group1 accepted** after verified VPS reboot; no replay. Next [unattended gateway foundation](paytm-gateway-foundation.md) batches engineering recovery/security/process tests and Windows SSH compatibility. Production adapters, custody, installation and real lifecycle remain pending. **1/6 acceptance groups complete (16.7% of the Paytm-readiness checklist only)**; five groups unchanged, not five guaranteed test runs or whole-project progress. Earlier immediate-next-step notes are historical.

2026-10-23 E181/E182: Before stopped on a defective disabled-state assumption for the original static gateway. [Corrected precheck](paytm-maintenance-completion.md) ready for fresh runtime validation; no reboot occurred or package acceptance regressed. Maintenance group1 remains open, five downstream groups unchanged. Bug correction adds no project percentage.

2026-10-23 E179/E180: scanner install/scan accepted; six stale services/four sessions remain. [Confirmed reboot and fresh postcheck](paytm-maintenance-completion.md) combines the remaining guest restart work, with no reinstall. Maintenance group1 remains open until real acceptance; five further groups unchanged. VM microcode is a separately recorded provider limitation, not a guest pass or automatic reboot requirement. No whole-project percentage increment.

2026-10-23 E177/E178: scanner dependency plan accepted, six packages/no upgrades/removals. [Install plus scan](paytm-scanner-install.md) now combined in one controlled job; real execution and restart review remain pending inside maintenance group1 of six. No additional milestone group or overall percentage gain for preparation.

2026-10-23 E175/E176: restart collection accepted with scanner unavailable, not maintenance complete. [Read-only dependency preview](paytm-scanner-plan.md) addresses that specific gap; no completed-update replay, installation or activation. Still group1 of six; no project-percentage increment for local tests or diagnosis.

2026-10-23 E173/E174: update checkpoint accepted (70 targets/postchecks, fresh login,159.754s); maintenance group1 remains open for [read-only restart review](paytm-restart-review.md). No repeat installation or added milestone group. Remaining unattended/login/quotes/Telegram gates and overall percentages unchanged.

2026-10-23 E172: maintenance update blocked safely before install; one tzdata candidate drift identified. [Reviewed r2 retry](paytm-maintenance-update.md) prepared with original evidence preserved and fresh guards. Maintenance batch1 still open; no added milestone group, no overall percentage increment.

2026-10-23 E170/E171: backup runtime acceptance closes that checkpoint (95.89s, comparison passed), not maintenance as a whole. [Controlled exact-version updates/postchecks](paytm-maintenance-update.md) prepared; actual install/fresh login/restart review pending. Still batch1 of six acceptance groups. No whole-roadmap percentage gain or guaranteed remaining run count.

2026-10-23 E168/E169: maintenance preflight accepted; owner-tested independent console access confirmed. [Private configuration/package backup](paytm-maintenance-backup.md) next, locally verified but not yet executed on VPS. Batch1 remains incomplete until reviewed recovery/update/post-checks; remaining six-group scope unchanged. No whole-project percentage uplift.

2026-10-23 E166/E167 current: relative clock snapshot accepted10/10 in100.465s total; automatic synchronization/quote timing still unproven. [Consolidated maintenance preflight](paytm-maintenance-plan.md) next, locally verified but spare pending. Six remaining milestone batches before paper-execution integration, not a guaranteed retry count. No whole-roadmap percentage increase.

2026-10-22 E164/E165 current: owner manually corrected Windows and reports<5s VPS difference. [Read-only three-clock snapshot](paytm-clock-snapshot.md) is next; runtime accuracy, ongoing drift policy and VPS package maintenance remain open. This supersedes the Windows-only diagnosis as the next command, not the unresolved automatic-sync issue. No rebuild/gateway/trade activation or overall percentage increment.

2026-10-22 E162/E163 current next step: VPS package-index refresh accepted;70 update candidates require separate maintenance review. Elevation passed but Windows Time service access denied, resync unattempted. [Windows-only access diagnosis](paytm-windows-time-access.md) is locally verified, actual spare diagnosis/repair pending. Main route8/8 remains accepted; unattended activation, login/quotes and paper-return gates remain open. No new full-roadmap percentage inferred from this operational finding. Older next-action entries below are historical.

2026-10-15 E138: application handoff remains60% after a pre-build configuration rejection on spare. [Corrected retry](paper-runtime-application-handoff.md) has314 offline assertions/14 mocked scenarios, not spare deployment proof. Repair gain0pp; isolated custody100%, access-policy80% and full-roadmap12.4% unchanged. No role, approval or order authority added.

2026-10-15 E136/E137: the isolated runtime test is accepted at100%:18 unique Linux checks repeated after restart, protected synthetic handoff, final LOCKED and cleanup verified in91.716s. Do not rerun it. Next is the [guarded application handoff](paper-runtime-application-handoff.md), locally verified60% with236 offline assertions/12 mocked scenarios. It rebuilds/recreates only the service, briefly hands over the existing protected credential, verifies locked restart and re-locks. PostgreSQL remains NOLOGIN; no proposal publication or account writes. Real deployment verification and owner acceptance are pending; full-roadmap12.4% and effective-access review80% remain unchanged. Earlier next-action paragraphs below are historical.

2026-10-15 E135: isolated runtime verification failed on the synthetic pairing-code length, not real credentials. The [fixture correction and retry](paper-runtime-credential-handoff.md) retain package60%, full-roadmap12.4% and access-policy80%; repair gain0pp. Actual handoff/restart proof and owner acceptance remain pending. Do not count the passed image build as completed runtime verification.

2026-10-15 E134: approved policy/custody implementation is locally verified60% within the [bounded runtime handoff package](paper-runtime-credential-handoff.md).779 Java tests and112 offline PowerShell assertions pass;18 isolated Linux checks await the spare. No real credential or runtime deployment. Full-roadmap12.4% and access-policy80% remain unchanged. Actual guarded activation/publication, durable Telegram outcomes, paper execution and numerical validation are still separate gates. Older unresolved policy-choice statements below are superseded.

2026-10-14 E133: bounded deployed authentication/revocation accepted at100% (60% to80% runtime, then100% owner acceptance).19 successful stages, three probes and17 source matches; writer/helper NOLOGIN and zero sessions restored. Full-roadmap12.4% and access-policy80% unchanged. [Next runtime review implementation](paper-runtime-review-plan.md) awaits test-limit and restart-custody choices; no next-package completion credit. The E131/E132 handoff below is historical.

2026-10-14 E131/E132: protected credential staging is accepted at100%, five successful stages, 11 source matches and24.077s. Next is [bounded application-container authentication/revocation](paper-writer-authentication.md): an explicitly confirmed120-second password lease, actual deployed connector checks, negative access tests, committed NOLOGIN and recovery. This package is locally verified60%, spare pending. Persistent runtime handoff, policy limits, real Telegram approval, paper execution and predictor validation remain unfinished. Access-policy acceptance80%, full-roadmap12.4% unchanged. No repeat HBA/credential staging; phone portal/Tailscale are not prerequisite gates. Earlier handoffs below are historical.

Baseline: MB-PLAN-2026-09-18-V2. Authority: [documentation index](README.md). Evidence: [register](evidence-register.md). Daily changes: [progress log](daily-progress.md). PG1 is the complete intelligence/eventual live product; PG2 is its mandatory paper-first deployment. Goal IDs remain stable when scope is corrected.

## How percentages work

2026-10-13 E125/E126: actual HBA staging passes spare verification and owner acceptance, moving its bounded package from 60% to 100% (+40pp including R/A). Thirteen successful subprocesses, 11 source matches, four added rules, zero parse errors and fresh application access are verified; writer stays NOLOGIN. Do not rerun Apply. Next is [targeted read-only network review](paper-writer-network-review.md) for two saved broad firewall entries, not activation. The 225 offline assertions add no separate parent-goal credit. Existing access review remains 80%; full roadmap 12.4%. No firewall change, credential activation or execution is enabled. Older handoffs below are historical.

2026-10-13 E114: restricted writer **Stage 1 preparation 60%** (D/I/V), spare R and owner A pending. This new package excludes real staging/authentication and earns no completed parent milestone yet. E113 access review remains 80%, full roadmap 12.4%. [Run the preparation bundle](paper-writer-restricted-access-plan.md), not yesterday's general diagnostic.

Current E113 update: foundation is 100%; targeted application-route/authentication/firewall review is runtime verified at 80% (60% to 80%, +20pp), with policy findings/owner acceptance pending. These are bounded packages, not the whole writer or portal. Full-roadmap 12.4% unchanged; TLS remains deferred. [Next scoped restriction plan](paper-writer-restricted-access-plan.md) is documentation only, not a server change or another test run. Older next-stage text below is historical.

2026-10-12: E97 recovery, E99 restricted writer, E101 preflight, E104 NOLOGIN staging and E107 connection inventory are accepted. E108 [local writer foundation](paper-writer-local-foundation.md) implements an unwired connector and synthetic custody with combined local-boundary collection. Owner-approved policy: private single laptop, TLS deferred. Foundation spare verification, actual private route, real credential handoff and application review wiring remain pending. The [daily scorecard](daily-scorecard.md) separates packages; full-goal baseline stays 12.4%. No forecast accuracy or whole G08/G09/G10 completion follows from these checks.

These percentages measure engineering delivery, **not investment accuracy, probability of profit, or confidence in a model**. This is a new, broader scope; it must not be compared with old experimental scorecards or a previously quoted project percentage.

Each delivery goal has five binary checkpoints. A checkpoint earns its entire weight only when its stated scope is complete; partial work remains visible in the subitems without earning the whole checkpoint.

| Checkpoint | Weight | Required evidence |
|---|---:|---|
| D: design recorded | 10% | Reviewable scope, contracts, safety boundary and acceptance criteria in this baseline; owner acceptance is a separate checkpoint |
| I: implementation present | 30% | Complete scoped implementation in versioned source; presence is not proof of correctness |
| V: offline verified | 20% | Reproducible passing tests against the identified implementation revision |
| R: runtime verified | 20% | Spare-laptop evidence satisfying the goal's integration criteria |
| A: accepted | 20% | Owner accepts the scoped evidence and all goal-specific safety/quality criteria |

No credit for anticipated results, expired evidence, undocumented assumptions or a failed test. A superseding change invalidates affected verification checkpoints until rechecked. Record numerator/denominator as well as percentages. Historical functionality is acknowledged, but old runtime claims do not establish current deployment readiness.

## Current dashboard

**E96/E97 update, 2026-10-09:** application storage/key attachment accepted:12/12 checks, unchanged INR100,000, zero reserves/revision and verified key. [Recovery and audit permissions](paper-recovery-verification.md) now bundles14 synthetic backup/restore/quarantine/permission checks. No application restart; spare verification pending. Actual production backup restore, scoped approval writer, governed key rotation/reconciliation, real transport and risk/execution remain gates. This closes only partial Phase3 storage acceptance; **12.4%** full-goal baseline unchanged. Earlier E95 spare-pending wording is historical.

**E94/E95 update, 2026-10-09:** 24/24 delivery/recovery checks accepted in 199.542s. [Approval storage/key attachment](paper-approval-storage.md) implements V28, explicit persistent key setup and read-only readiness. The next handoff gates application deployment behind 12 new isolated checks and database/key backup confirmations, then checks the unchanged account and disabled capabilities. Real transport, dedicated writer permissions, risk policy and paper execution remain pending. Partial Phase 3 progress does not complete G08/G09; **12.4%** parent baseline unchanged. Older E93 pending wording is superseded.

**E92/E93 update, 2026-10-09:** all 32 isolated approval checks passed on spare in185.262s; no repeat needed. [Delivery integration rehearsal](paper-delivery-integration.md) now adds atomic encrypted outbox creation, single-attempt delivery, optional private callback routing and bounded strict Upstox/Telegram adapters. Twenty-four combined database/restart checks await spare acceptance with fake HTTP only. Application migration/key management, real transport, approved risk and execution remain blocked. Partial Phase3 engineering leaves the full parent baseline **12.4%** unchanged. Older E91 spare-pending text is superseded within this accepted scope.

**E90/E91 update, 2026-10-09:** application ledger/readback and owner Read/Refresh + Clear/Lock screenshots are accepted: existing INR100,000, zero reserves, revision0. [Approval review candidate](paper-approval-review.md) now implements proposal-bound one-time tokens, recipient/expiry/account/policy checks and terminal review receipts without cash/order effects. Next is a single 32-case isolated database bundle; Telegram/provider/ledger execution wiring remains blocked. The E89 application-deployment gate below is closed. Partial G08/G09 progress does not yet earn a complete parent checkpoint; weighted baseline remains 12.4%.

**E88/E89 update, 2026-10-09:** all 31 isolated ledger checks passed in 218.014s, with database restart recovery and owned-resource cleanup. [Spare acceptance](evidence/paper-ledger-spare-acceptance-20261009.json). V27 now adopts the verified SQL; a V2 read-only portal exposes only validated opening cash/reserves. [Guarded application deployment](paper-application-ledger.md#application-attachment-handoff) is next; authentication/risk integration, command ingress, operational balances and P&L remain pending. Older isolated-pending/candidate-only wording below is superseded. Partial G08/G09 progress does not complete parent checkpoints; weighted 12.4% unchanged.

**E86/E87 update, 2026-10-09:** Phase 1 read-only account integration is spare-verified and owner-accepted: account #1 and INR100,000 preserved. Phase 2 [ledger candidate](paper-application-ledger.md) now implements indexed durable commands/projections, reservations and partial-fill/cancel/expiry lifecycle, with 518 Java tests and 80 offline PowerShell assertions passing. Thirty-one new isolated database checks await spare evidence. Candidate SQL is outside Flyway; authenticated commands, application adoption and operational portfolio views remain pending. This supersedes E85's Phase 1 spare-pending wording only; parent G08/G09 checkpoints and weighted 12.4% remain unchanged.

**E84/E85 update, 2026-10-09:** incident reconciliation is closed on spare; [accepted replay](evidence/feature-reconciliation-acceptance-20261009.json) shows COMPLETED and notification SENT with no writes. Authorized [paper integration plan](paper-application-integration-plan.md) now has Phase 1 source/offline verification: existing-account read API, token guard and portal. G08.1/G09 advance in bounded implementation only; full parent checkpoints and weighted 12.4% remain unchanged. Spare verification and browser acceptance pending. G08.2–G08.5 durable application accounting/execution and authenticated approvals remain next, not completed by this read-only slice. Older E83 pending wording below is superseded.

**Historical E82/E83 update, 2026-10-09:** October 8 snapshot persistence is verified: 500 items, 487 vectors, 13 withheld, matching manifest. E76 isolated PostgreSQL and E73 preparation remain accepted; do not repeat. E83 [automation reconciliation](reviewed-feature-reconciliation.md) links this exact saved snapshot to the stopped checkpoint with a durable review audit; deployment/apply pending. Old warning history and prior reviewer-label caveat stay retained. No feature regeneration, raw-price repair, fitting or trade release. Upstox source policy and paper application/portal integration remain pending; full-paper-first weighted completion stays 12.4%. Feature availability of 97.4% is not project completion or predictive accuracy.

E71 closed E69/E70 evidence-store spare verification: 22/22 checks in 4.254 seconds. Saved-snapshot assessment and standalone append-only storage remain accepted within their synthetic scope. No repeated storage/export verification, live collector or market fit is requested.

Earlier accepted E68: [ten-feature engineering spare acceptance](evidence/numerical-ten-feature-spare-acceptance-20260919.json), 32/32 checks in 8.900s on PS7.6.6/native Java25. The bounded engineering checkpoint is closed; no repeated synthetic or E65 mapping/export run. Owner approved [preparing both research tracks](numerical-research-scope-decision.md); saved snapshot hashes and prospective timestamp/record requirements are pinned in a non-runtime plan. Source facts, operational capture settings and market evaluation criteria remain open. E65's 600 rows/150 dates still have 0 point-in-time training-eligible rows; retrospective eligibility is unassessed, not approved. Dashboard percentages remain unchanged: engineering acceptance is not a validated market predictor or full G03 release.

The revised paper-first baseline is **12.4% engineering delivery**: `(8 × 40 + 92 × 10) / 100`. This replaces V1's 13% because history, fundamentals and governed learning now have explicit weights; **the -0.6 percentage-point change is scope rebaselining, not lost implementation or worse model performance**. Weights are declared planning weights, not measured effort or accuracy. G01 retains its narrowly scoped implementation-presence checkpoint; the other included goals have design credit only. No V/R/A delivery checkpoints are claimed. Owner agreement with the scope is not acceptance of an implemented feature.

This denominator covers the full paper-first target, including shared PG1 foundations, not the future live release. G12 remains separately tracked at 0%; do not call 100% of this dashboard 100% of PG1. **Live-order readiness is not approved; numerical predictive performance is unmeasured.**

| Goal | Scope | Weight | Checkpoints | Completion | Area status / pending work |
|---|---|---:|---|---:|---|
| G01 | Verify existing Upstox REST and historical/daily pipeline | 8 | D, I | 40% | Implemented foundation; refresh tests, runtime and data-coverage evidence |
| G02 | Point-in-time, multi-date prediction dataset | 8 | D | 10% | Prototype datasets exist; executable labels, vintage data and leakage controls pending |
| G03 | Numerical 20-session swing predictor | 12 | D | 10% | Synthetic learner/evaluation engineering verified; no market-fitted/calibrated predictor established |
| G04 | Upstox streaming and live aggregation | 7 | D | 10% | REST is not streaming; streaming implementation pending |
| G05 | Paytm live market data, read-only | 5 | D | 10% | Historical client exists; current live API/auth/entitlement verification and integration pending |
| G06 | Governed Marketaux ingestion and news features | 5 | D | 10% | Ingestion foundations exist; reliable entity/event pipeline pending |
| G07 | Required 5/60-session swing and separate intraday prediction | 8 | D | 10% | With G03 covers 5/20/60 sessions; 10 sessions optional, intraday initially 30/60 minutes |
| G08 | INR 100,000 paper account, orders and fills | 9 | D | 10% | SQL foundations and offline core verified; durable integration, realistic fills, P&L and portal pending |
| G09 | Functional portal, approval and notifications | 8 | D | 10% | Static UI and notification foundations; end-to-end paper workflow pending |
| G10 | Integrated security, operations and recovery | 5 | D | 10% | Existing safeguards to reuse; full release verification pending |
| G11 | Prospective month-plus paper validation | 8 | D | 10% | Trial protocol designed; final 60-session outcomes need additional maturation |
| G12 | Paytm real order execution | Excluded | None | 0% | Deferred; separate authorization and release decision required |
| G13 | 15+ year history target and frequency-specific coverage | 7 | D | 10% | Dedicated acquisition/licensing/membership/retention plan; actual coverage unverified |
| G14 | Point-in-time fundamental intelligence | 5 | D | 10% | Financial-statement, valuation and earnings features designed; implementation not established |
| G15 | Feedback, outcome learning and controlled retraining | 5 | D | 10% | Preference/outcome separation, challenger evaluation and promotion/rollback designed |

G00, the documentation/evidence-reset task, is tracked separately: **4/5 checkpoints (80%)** — inventory mapped, canonical plan written, evidence/uncertainty register written, and owner acceptance of the parent scope/clarifications recorded. Exhaustive source-review coverage remains pending. This does not approve detailed risk defaults, implementation or live trading. A broad repository scan is not a certified line-by-line audit.

## Parent-goal traceability

| Accepted requirement | Owning subgoals | Acceptance evidence |
|---|---|---|
| PG1: 15+ years, all eligible Nifty 500 companies | G13.1–G13.5, G01, G02 | Frequency-specific licensed coverage matrix; listing/membership history and explicit gaps |
| PG1: technical, quantitative, fundamental and news analysis | G02/G03, G06, G14.1–G14.5 | Point-in-time features, numerical validation and source-specific ablation |
| PG1: 5/20/60-session research/forecasts plus intraday | G03, G07.1–G07.5 | Separate lookback/forecast fields; independently validated horizons |
| PG1: autonomous analysis with Telegram ACCEPT/REJECT | G04/G05, G09.4, G09.6 | Scheduled/event-driven proposals; acceptance cannot bypass fresh risk/price checks |
| PG1: feedback and outcome learning | G15.1–G15.5 | Auditable feedback/outcomes, versioned challenger tests, governed promotion and rollback |
| PG1: eventually execute approved Paytm trades | G12.1–G12.5 | Separately approved live adapter, reconciliation, position monitoring and kill-switch tests |
| PG2: one INR 100,000 realistic paper account | G08.1–G08.6 | Cash/holdings reconciliation; conservative costs/fills; no double-spending |
| PG2: preserve production data/prediction/approval workflow | G08.5, G09.6, G10.5 | Shared contracts and adapter conformance; no broker order calls in paper mode |
| PG2: experimentation and comprehensive simulation | G08.6, G11, G15 | Isolated research simulation, frozen prospective cohorts and matured outcomes |

## Work items and acceptance gates

Legend: `DONE-SOURCE` = found in source, `PARTIAL` = reusable but incomplete for this goal, `DESIGNED` = specified here, `PENDING` = no accepted implementation/evidence. These labels are not additional numerical checkpoints.

The V1 working-day windows below are retained only as **prior core-work sequencing estimates**, not current delivery dates for the expanded V2 scope. The revised evidence-first scheduling gate at the end of this document supersedes the former overall estimate.

### Immediate start package — evidence and environment preflight

G10.6 scoped LLM cleanup is **completed and owner-accepted on 2026-09-18**, evidence E26. Granite removed, Qwen 0.5B quarantined, Qwen 1.5B retained with matching hashes, service health UP. Ollama and llama.cpp retained. Broader runtime/job inventory limitations remain under G10.3; no predictive-performance credit follows from cleanup.

Next: reuse existing Upstox quality evidence (E31) in G02's [numerical baseline work package](numerical-baseline-plan.md). N1 audit and N2 bounded history results are reviewed (E28/E30): 476/500 eligible, 24 insufficient-history. Research-label arithmetic is offline verified (E32); real calendar/price-policy integration, contract freeze and multi-date export remain pending. No repeat acquisition, provider validation sweep, model download or training is requested. Supporting components do not earn completion of the full prediction-grade dataset: weighted baseline remains 12.4%.

| First work lane | Bounded output | Boundary |
|---|---|---|
| Environment preflight: G10.6 | Completed: reviewed inventories, confirmed scoped cleanup and verification | No further removal; quarantine/report retained for recovery |
| Data readiness: G01/G13/G14 | Current revision, provider access and coverage matrix; identify usable historical data and fundamental-source gaps | Reuse saved reports first; bounded queries only after review; no broad backfill yet |
| First implementation design: G02/G08/G09 | 20-session feature/label contract plus INR 100,000 ledger/approval contract and portal wireframes | No application implementation until the owner approves the bounded slice; no live orders |

After evidence/contract approval, the proposed first build is the prediction-grade 20-session dataset and deterministic paper-account foundation. These are independent work lanes with a shared contract. Numerical baseline training follows dataset validation; required 5/60-session and intraday expansion follows separate evidence gates. LLM prompt tuning is not the critical path for this numerical engine.

### G01 — Existing Upstox REST and daily foundation

- G01.1 `DONE-SOURCE`: instrument import, quotes, historical/intraday candle import and corporate-action access; evidence E02.
- G01.2 `DONE-SOURCE`: persisted historical backfill, daily enrichment, technical snapshots; E03.
- G01.3 `PENDING`: verify tests at an identified revision, authentication, entitlement, canonical instrument mapping and current deployment configuration without exposing credentials.
- G01.4 `PENDING`: collect actual Nifty 500 coverage, missing sessions, duplicates, corporate-action adjustments, source priority, recovery and backup/restore evidence.
- Acceptance: all declared operations pass contract tests and a bounded spare-laptop check; coverage report explicitly lists unavailable symbols/dates; no claim of second-by-second streaming from REST. A data-readiness threshold is frozen before G02 acceptance; critical missing features cause exclusion, never silent imputation.
- Dependencies: G00 scope/evidence approval. Proposed window: D1–D10. Responsible roles: implementation engineer; owner supplies account/access evidence and accepts.

### G02 — Prediction-grade dataset

E54 external dependency: **PENDING_EXTERNAL_REPLY**. Owner reports the neutral Upstox email sent; no ticket/answer supplied. Source-policy certification remains pending, not failed or completed. Preserve the existing export; no repeat collection. [Reply handoff and independent evaluation-engineering contract](numerical-evaluation-engineering-plan.md).

- G02.1 `PARTIAL`: prototype immutable runs and 5/20/60-session outcome labels exist; E04.
- G02.2 `PARTIAL`: history/features/calendar/quality linkage and outcome paths verified within scope; E47 confirms the 38-date export on spare. E50 verifies repair capture in 8.828s with four reviewed job links but no scoped adjustment references. E52 verifies expanded **uncertified** arithmetic on spare: 150 dates/600 rows in 19.824s, previous values unchanged. E53 records source-policy findings and exact clarification needed; no repeat export/empty repair query. No new acquisition or gate relaxation. Price/availability/universe policy, certified export, valid frozen folds and a genuinely untouched evaluation set remain pending. No training authorization or overall percentage increase from preparatory slices. Conditional engineering estimate remains in the numerical plan; full platform/paper observation separate.
- G02.3 `PENDING`: multi-date export; identify survivorship limitations when historical constituents are unavailable; separate adjusted features from tradable prices.
- G02.4 `PENDING`: chronological train/tune/final partitions, overlap purging, future-field exclusion, duplicate/vintage checks and reproducible hashes.
- G02.5 `PENDING`: tests for suspended stocks, missing bars, insufficient warm-up, holidays, delisting and stale news.
- Acceptance: every feature is available by decision time; outcomes are excluded from inference; split manifests reproducible; all leakage and label tests pass. Unresolved source coverage/licensing gaps block the affected dataset, not silently disappear.
- Dependencies: G01 data evidence; source permissions. Window: D6–D20. Owner: data/implementation role.

### G03 — Numerical 20-session swing predictor

Independent engineering packages are spare verified through E60: **47/47 checks, nine folds, 34.368s**, covering 5/20/60-session synthetic plumbing and hypothetical costs. This bounded phase is complete; no repeat requested. E61 [contract review](numerical-market-contract-review.md) groups six associated subgoals. E62 approves only the initial restricted 20-session price-return research scope; E63 implements/offline verifies the ten-feature mapper, eligibility ledger and date coverage. Remaining source/production/evaluation decisions and evidence are still open. This prepares G03/G02/G07 without closing real-data prerequisites or changing whole-goal percentages. Upstox reply remains pending; fitting and final split freeze remain blocked. The two-feature synthetic fitter cannot consume the ten-feature DTO; no production-model readiness is inferred.

- G03.1 `DESIGNED`: compare no-action/current deterministic baseline with a simple linear learner and a bounded small tree-model search; no guaranteed winner.
- G03.2 `PENDING`: fit numerical models on training data only; record parameters, feature versions, seeds, cost assumptions and rejected experiments.
- G03.3 `PENDING`: rolling validation, calibration where probabilities are emitted, cost sensitivity, date-grouped uncertainty and stability by sector/regime.
- G03.4 `PENDING`: untouched final test; inference parity check; versioned model promotion/rollback and stale-input abstention.
- G03.5 `PENDING`: compare AI-assisted decisions against Java-only decisions using the same dates, universe, costs and risk limits.
- Acceptance: pre-register the primary out-of-sample metric and minimum effect before opening final test results; assess drawdown, turnover and uncertainty as well as return. If the edge is inconclusive or negative, retain the baseline and mark this goal unaccepted. A valid JSON response or Java agreement is not predictive evidence.
- Dependencies: G02; cannot train first and fix leakage afterward. Window: D11–D30. Owner: numerical-model/implementation role.

### G04 — Upstox live feed

- G04.1 `DESIGNED`: streaming adapter, instrument mapping, connection lifecycle and event/receipt timestamps; E12.
- G04.2 `PENDING`: bounded queue, reconnect/backoff, gap detection, deduplication and persisted minute bars.
- G04.3 `PENDING`: freshness/source-health rules; halt affected decisions on stale or incomplete input; controlled historical backfill.
- G04.4 `PENDING`: replay and market-hours load test for subscribed Nifty 500 coverage within actual account limits.
- Acceptance: supported subscription limits are recorded; simulated disconnects cannot silently produce fresh-looking signals; measured queue lag, dropped events, bar completeness and reconnect times satisfy frozen operational limits. No assumption that every symbol receives a tick every second.
- Dependencies: G01 identity/auth evidence; streaming entitlement. Window: D16–D30. Owner: provider/implementation role.

### G05 — Paytm live data only

E159/E160: main Spring route remains accepted 8/8 in 456.253 seconds. [Operations snapshot](evidence/paytm-operations-spare-review-20261022.json) captured with findings in 134.148 seconds: expected IP/configuration/stopped state, clock disagreement and cached maintenance. [Combined follow-up](paytm-operations-followup.md) corrects tinyproxy-bin lookup, requests configured-source Windows resync and VPS index refresh/simulation; VPS time unchanged, no package installation. Local 44 new/52 existing PowerShell assertions and 31 Bash assertions pass; follow-up runtime pending. [Unattended gateway design before login](paytm-unattended-gateway-plan.md) remains proposed, not activated. No G05 or whole-roadmap percentage increase from diagnostic transport/collection alone.

E144 accepts human administrator key login/sudo. E145 prepares [loopback proxy staging](paytm-loopback-gateway.md); no live-data credit. VPS runtime tests, restricted SSH transport, actual-container proxy/fail-closed verification and authentication remain separate pending gates. Do not enable the existing direct historical client based on VPS-only evidence.

E143: [VPS administrator installation](vps-admin-installation.md) prepared with collision/policy guards and retained root recovery. Real key login and administrative verification are pending. This is infrastructure preparation, not gateway or G05 live-data completion; no percentage increase.

E142: VPS baseline reviewed; [local administrative key creation](vps-administrative-key-setup.md) is next. Three launcher scenarios pass offline; real key installation/second login, gateway routing and Paytm authentication remain pending. No G05 percentage increase is inferred from inventory or launcher tests. The baseline-pending note below is historical.

E141: independent-console/PuTTY host-key comparison is accepted; [read-only VPS baseline](paytm-gateway-preflight.md) is next. Actual baseline, gateway configuration and application-path routing tests are still pending. Identity verification alone grants no live-authentication or G05 completion credit.

E140: the synthetic login subpackage is now accepted100% after38 spare checks and owner continuation. No G05/live-authentication percentage is inferred. Next is [provider-console identity verification](paytm-gateway-preflight.md); the OS-configuration reply did not establish the SSH fingerprint. Actual gateway, callback ingress, token exchange and quotes remain pending.

2026-10-21 E139: app registration is Active per screenshot. [Synthetic login/callback preparation](paytm-login-preparation.md) is a bounded subpackage, not completion of authentication or G05. Native spare rehearsal needs no keys or restart. VPS identity, actual application egress, live callback contract, token exchange and quotes remain pending; no parent-goal percentage credit is inferred.

- G05.1 `PARTIAL`: historical price-chart client exists; this is not live-data or order integration; E05.
- G05.2 `PENDING`: obtain current official account-specific auth, market-feed contract, exchange entitlement, rate limits and static-egress requirements; no secrets in documentation.
- G05.3 `DESIGNED`: normalized read-only adapter, source provenance, explicit preference/failover policy and divergence alarms.
- G05.4 `PENDING`: test expiration, reconnect, throttling, permissions, duplicate/missing data and cross-provider consistency.
- Acceptance: bounded live-data checks pass and failure cannot trigger broker orders; read-only credentials/permissions used where supported; no create/modify/cancel-order call path enabled. Missing account/network prerequisites remain an external blocker.
- Dependencies: provider approval/network setup separately authorized; G01 identifiers; G04 shared feed contract. Window: access work D1 onward, implementation D26–D35 if ready. Owner: owner for access, engineer for integration.

### G06 — Marketaux and company events

- G06.1 `PARTIAL`: connector, ingestion audit and permission-related tables exist; E06.
- G06.2 `PENDING`: durable company/ISIN mapping, ambiguous-match rejection, first-seen versus publication times, clustering and revisions.
- G06.3 `PENDING`: enforce actual daily quotas, network timeouts, backoff, scheduling and licensed retention/deletion.
- G06.4 `DESIGNED`: optional small-model structured extraction with article evidence, bounded enums, uncertainty and adversarial-input tests; model cannot issue executable commands.
- G06.5 `PENDING`: news-triggered reassessment of eligible companies; event features and historical availability tests.
- Acceptance: labelled entity/event evaluation and error categories documented; no ambiguous entity silently routes a trade proposal; duplicate news does not duplicate proposals; no future news enters historical features. Degrade explicitly to a no-news baseline when permitted, otherwise abstain.
- Dependencies: source entitlement and G02/G04 input contracts. Window: D6–D35 alongside provider waiting periods. Owner: data/implementation role; owner confirms subscription rights.

### G07 — Additional horizons and intraday

- G07.1 `DESIGNED`: required 5/60-session models alongside G03's 20-session model, plus separate 30/60-minute intraday labels, calibration and policies. Ten-session forecasting is optional, not a substitute for 60 sessions.
- G07.2 `PENDING`: validate executable 5/60-session labels and obtain sufficient point-in-time intraday history with spread/volume/session constraints; existing prototype labels do not establish valid forecasting models.
- G07.3 `PENDING`: horizon-specific chronological validation and no-news versus news-feature ablation.
- G07.4 `PENDING`: session-close handling, position-horizon conflicts and bounded inference scheduling.
- G07.5 `DESIGNED`: distinguish historical lookback (including 5/20/60-session diagnostics) from forward forecast horizon; test each combination without future information. HOLD produces no order; unreliable evidence permits NO_TRADE/ABSTAIN.
- Acceptance: each advertised horizon independently meets G03-style evidence requirements. Insufficient intraday history blocks that mode. Disabled modes must be visibly disabled in the portal.
- Dependencies: G02/G03 validation framework; G04, G06 for full live/news-enabled scope. Window: D26–D45, possibly contingency. Owner: numerical-model/implementation role.

### G08 — Paper accounting and execution

- G08.1 `PARTIAL`: seed for INR 100,000 portfolio plus order/fill tables exist; no complete simulator demonstrated; E07.
- G08.2 `PARTIAL` E72: offline exact-paise account, reservations, holdings, supplied fees and in-memory audit verified; durable shared accounting and realised/unrealised P&L pending.
- G08.3 `PARTIAL` E72: fixture lifecycle, idempotency, fresh-price/risk checks, partial fills and cancellation/expiry verified; authenticated integration and exchange-realistic execution policy pending.
- G08.4 `PARTIAL` E76: reconciliation, overflow, concurrency, bounded PostgreSQL transaction/replay and isolated restart recovery verified on spare (24/24). Application integration, corporate actions, settlement, hardware-loss recovery and broader property tests remain pending.
- G08.5 `DESIGNED`: share data, prediction, proposal, risk, approval and order-intent contracts with the future production workflow; a separately authorized broker adapter will differ from the paper adapter. Require contract conformance, not identical fill outcomes.
- G08.6 `DESIGNED`: isolate the approved INR 100,000 portfolio from research simulation of rejected/unapproved proposals. Never reserve/spend approved-account cash for hypothetical trades; preserve distinct IDs, costs and assumptions.
- Acceptance: paise-level ledger reconciliation, no negative available cash/overselling, one approval cannot create duplicate fills, crash replay preserves balances. Real broker order placement remains absent/disabled by construction.
- Dependencies: approved risk/fill contracts; G01 for fixtures, G04/G05 for final runtime tests. Window: D6–D25. Owner: backend/implementation role.

### G09 — Portal and human decision workflow

- G09.1 `PARTIAL`: static React dashboard and Telegram/WhatsApp foundations exist; E08.
- G09.2 `DESIGNED`: screens in [system design](system-design.md), clear PAPER badge and INR 100,000 initial account.
- G09.3 `PENDING`: authenticated APIs/UI, evidence view, approvals, order/position history and integration health.
- G09.4 `PENDING`: Java-templated alerts with user-facing ACCEPT / REJECT; one-time expiring approvals shared across portal/Telegram; WhatsApp optional and non-blocking. ACCEPT maps to an approval event, not a guaranteed fill.
- G09.5 `PENDING`: accessible error states, stale-price expiry, duplicate-click tests, no accidental live controls and compact report export.
- G09.6 `DESIGNED`: preserve identical proposal/risk/approval semantics for paper and eventual live workflows; explicitly label PAPER versus RESEARCH SIMULATION results. HOLD records an assessment without order execution; accepting a BUY/SELL still allows risk rejection or order expiry.
- Acceptance: end-to-end proposal → human approval → price/risk revalidation → paper fill → ledger → report passes; expired/out-of-zone approval cannot buy. UI never presents a score as a guaranteed outcome.
- Dependencies: G08 contract; real predictions require G03/G07. Window: design D1–D5; implementation D11–D35. Owner: frontend/backend role; owner acceptance.

### G10 — Release hardening

- G10.1 `DESIGNED`: access, secret handling, audit, backup/restore and review-only execution boundary.
- G10.2 `PENDING`: tests for source outages, stale data, bad model output, approval races, disk full, power loss and restart.
- G10.3 `PENDING`: deployment revision/config evidence, dependency/security checks, health/readiness distinction and bounded load test.
- G10.4 `PENDING`: record response-time distributions, capacity and rejected/dropped work; rollback and runbook drill.
- G10.5 `DESIGNED`: shared-contract test suite and denied broker-order-call assertions for the paper release; future live-adapter tests cover partial fills, duplicate acknowledgements, unknown order states and reconciliation separately.
- G10.6 `COMPLETED-SCOPED / OWNER-ACCEPTED`: spare-machine approved LLM cleanup, E22–E26. All five **scoped cleanup** stages are closed; not a complete runtime/job/security audit and not a new weighted product goal:
  - Tooling available: `ops/windows/GetSpareLlmCleanupInventory.ps1`, with offline mocked tests. Run on the spare laptop and review its single JSON before crediting C1; tool implementation alone does not complete the inventory or cleanup.
  - C1 `DONE-SCOPED`: E22 inventories installed tags, known GGUF paths/sizes, processes and hardware counters; unavailable file versions/usable VRAM are explicitly unknown, not invented.
  - C2 `DONE-SCOPED`: source references/defaults reviewed, E24 runtime hints inspected, E26 records operator confirmation of idle/dependency conditions. Not independent proof of no queued Java job; partial scan and stale RUNNING evidence remain preserved.
  - C3 `DONE`: exact targets/recovery boundaries confirmed interactively (`operatorConfirmed=true`) and owner accepted the cleanup report in chat. No uninstall/process-stop authorization was used.
  - C4 `DONE`: digest-matched Granite removed via Ollama API; one Qwen 0.5B GGUF moved to verified same-volume quarantine; no recursive/shared-cache deletion.
  - C5 `DONE-SCOPED`: after list empty, 1.5B SHA256 unchanged, health UP, observed C: free-space increase 5,347,913,728 bytes. Quarantine recoverable; Granite restoration needs download. No inference or independent proof of all job/service health.
- Residual operational gaps move forward explicitly under G10.3: executable build provenance, actual usable VRAM, complete job/scheduler/deployed-config inventory and restart reconciliation. Owner acceptance closes **the scoped cleanup**, not those gaps. Keep quarantine/evidence; do not rerun removal. Cleanup does not earn G10's full I/V/R/A checkpoints or change the 12.4% weighted project baseline.
- Acceptance: no unresolved critical safety/security defect; restore test passes; one compact daily evidence bundle; all advertised workflows meet a written measured latency/capacity budget. Hardware capacity is measured, not assumed.
- Dependencies: G01–G09 plus G13–G15 for the full advertised paper scope. Prior core window: D36–D45, with tests throughout; revised dates follow the V2 scheduling gate. Owner: implementation/operator role.

### G11 — Prospective paper validation

- G11.1 `DESIGNED`: frozen model/policy versions, cash balance, benchmark, metrics and cohort dates before starting.
- G11.2 `PENDING`: at least **30 elapsed calendar days AND 20 actual exchange trading sessions**, whichever takes longer, with daily completeness checks.
- G11.3 `PENDING`: record all eligible proposals, approvals/rejections, abstentions, fills, costs, incidents and matched baseline outcomes—not just winners.
- G11.4 `PENDING`: obtain sufficient opportunities across declared modes; suggested operational floor of 20 decision dates per horizon and 10 closed paper trades overall requires owner approval and is **not** statistical proof. Extend observation if evidence is sparse; never manufacture trades to meet a quota.
- G11.5 `PENDING`: wait for every advertised horizon's final labels to mature, including the full 60-session forecast window; review uncertainty, risk, accounting and operating reliability; owner accepts, extends or rejects. A month of operation does not complete 60-session validation.
- Acceptance: data/audit continuity and reconciliation pass; no critical safety violation; predeclared model criteria pass on prospective evidence. A model with uncertain benefit remains advisory/disabled. Real money is still a separate decision under G12.
- Dependencies: accepted, advertised G01–G10 and G13–G15 scope, plus owner trial-start approval. An explicitly restricted pilot is possible but is not full G11 acceptance. Material changes open a new cohort and restart affected stability measurements; preserve old failures.

### G12 — Future Paytm execution, deliberately deferred

- G12.1 `PENDING`: separate feasibility, account permissions, policy/compliance and operational review.
- G12.2 `PENDING`: separately authorized design for create/modify/cancel orders, broker reconciliation, protective actions and kill switches.
- G12.3 `PENDING`: staged limits and independent go/no-go review after G11; passing a paper month is necessary evidence, not sufficient proof of live performance.
- G12.4 `PENDING`: broker acknowledgement/partial-fill/timeout/unknown-state reconciliation, idempotency, cancellation and manual recovery; never resend an uncertain order blindly.
- G12.5 `PENDING`: monitor actual positions and holdings after fills; refresh risk/exits, reconcile broker state and audit protective actions. Human approval or an explicitly preapproved protective rule remains authoritative, not model autonomy.
- No implementation date, current release weight or permission to place real orders. The portal must not gain live execution through a simple configuration toggle.

### G13 — 15+ year historical-data target

- G13.1 `DESIGNED`: inventory each required series by instrument, date range, frequency, provider, licence, publication/vintage availability and missing intervals. Separate daily, minute/tick, fundamentals and news coverage; do not assume one entitlement supplies all four.
- G13.2 `PENDING`: verify/acquire at least 15 years of daily price/volume history where the instrument existed and licensed sources permit, or since listing for newer companies. Exceptions require visible owner acceptance; unavailable data is not fabricated.
- G13.3 `PENDING`: version Nifty 500 membership over time, symbol/ISIN changes, delistings and corporate actions. Distinguish today's 500-company backfill from historical-universe evaluation.
- G13.4 `PENDING`: resumable bounded ingestion, reconciled gaps and revised data, immutable provenance, storage/retention and backup capacity; preserve raw versus adjusted values.
- G13.5 `PENDING`: publish frequency-specific coverage and quality dashboards, including intraday/news/fundamental limitations. Freeze required depth and tolerable gaps per mode before accepting it.
- Acceptance: audited coverage matrix and recovery test; missing or unlicensed series prevent full-coverage claims. A limited dataset may support an explicitly limited pilot, not completion of this goal.
- Dependencies: G01, source access and approved storage/licence budgets; informs G02/G07/G14. Owner: data engineer plus owner for entitlements. Timeline: feasibility during the first five authorized working days; acquisition ETA only after volume/rate-limit evidence.

### G14 — Point-in-time fundamental intelligence

- G14.1 `DESIGNED`: select authorized sources for financial statements, earnings, balance-sheet/cash-flow quality, valuation inputs and share counts; record separate historical depth/rights.
- G14.2 `PENDING`: normalize standalone/consolidated statements, reporting periods, currencies/units and company identifiers with provenance.
- G14.3 `PENDING`: preserve original publication/first-seen times, amendments and restatements; calculations use only the version available at prediction time.
- G14.4 `PENDING`: calculate versioned growth, profitability, leverage, cash-flow and valuation features; explicit stale/missing/sector-specific applicability rules.
- G14.5 `PENDING`: test ratio arithmetic and temporal joins, then compare numerical models with/without fundamentals on the same held-out dates and costs.
- Acceptance: no restatement leakage, validated calculations and coverage; inclusion in active prediction requires evidence of value, not merely successful ingestion. Report unsupported sectors/fields explicitly.
- Dependencies: G13 source feasibility, G02 identity/time contracts and G03 validation framework. Owner: data/numerical-model role. Timeline: source decision at the first scheduling gate; implementation estimate after sample-data review.

### G15 — Feedback, outcomes and controlled learning

- G15.1 `DESIGNED`: persist ACCEPT/REJECT/expiry and optional reasons separately from market outcome labels, forecast quality and execution quality. User preference is not proof of predictive correctness.
- G15.2 `PENDING`: attribute outcomes at each forecast horizon; track approved paper trades, hypothetical research trades and eventual real trades as distinct populations; include rejected/abstained opportunities where evaluation is defined.
- G15.3 `PENDING`: monitor drift, calibration, coverage and cost-adjusted performance; predefine cadence/triggers and minimum data before retraining. Never retrain on immature future labels.
- G15.4 `PENDING`: produce versioned challengers through bounded training/validation; predeclared improvement and risk gates, explicit promotion, frozen trial cohorts and rollback. An inconclusive challenger retains the incumbent.
- G15.5 `PENDING`: test corrupt feedback, duplicate outcomes, source corrections, regime shifts and rollback; audit why every model version was accepted or rejected.
- Acceptance: reproducible end-to-end feedback-to-challenger workflow, no preference/outcome conflation or active-model mutation during a frozen trial; no promise that every retraining cycle improves results.
- Dependencies: G03/G07 forecast contracts and mature outcomes, G08/G09 audit records; collect feedback early, promote only after validation. Owner: numerical-model/implementation role with owner promotion authority. Timeline: instrumentation alongside portal work, first retraining gate after sufficient mature data; no fixed improvement date.

## Parallel work and sequential gates

| Can progress concurrently when capacity permits | Must wait |
|---|---|
| G01 evidence, G05 provider/access questions, G09 wireframes, G06 licence review | No model acceptance before G02 data validation |
| G08 simulator using fixtures and G02 historical dataset | No paper fill integration before accounting/risk contracts |
| G04 feed adapter and G03 offline modelling | No live inference claim before feed freshness/recovery tests |
| G06 news pipeline and G09 portal against versioned contracts | No full multi-horizon acceptance before G07 validation |
| G13 coverage/licensing and G14 source samples alongside G08/G09 fixture work | No 15-year/fundamental completeness claim before audited coverage |
| G15 feedback instrumentation alongside portal implementation | No challenger promotion before mature outcomes and untouched validation |
| Daily documentation and tests alongside all authorized work | No G11 clock before integrated trial-entry gate; no G12 from paper results alone |

Roles are work lanes, **not an assumption of multiple developers**. With one engineer, parallel-ready tasks are interleaved; provider waiting and data collection can overlap. Model inference stays concurrency 1. No uncontrolled permutation loop or unbounded experiment search.

## Conditional timeline and daily cadence

**The former 45–60-working-day estimate and illustrative calendar dates are withdrawn for the expanded V2 scope.** Adding 15-year acquisition, fundamentals, 60-session validation and controlled learning requires data/access and capacity evidence before a credible replacement estimate. This is a scheduling reassessment, not an assertion that the work is impossible or already underway.

After explicit implementation authorization, use this first-five-working-day planning timebox (one engineering lane, no assumed extra staffing):

| Day | Bounded output | Owner/dependency |
|---|---|---|
| D1 | G10.6 read-only LLM/runtime inventory and dependency/cleanup proposal; deployed/source revision, review-coverage inventory and existing data reports | Engineer; owner runs bounded spare checks and approves exact cleanup targets before changes |
| D2 | G13 coverage/licensing/storage matrix and data-acquisition questions | Engineer; owner/provider for entitlement answers |
| D3 | G14 sample/source assessment; required 5/20/60-session and intraday contracts | Engineer; source samples/access may remain blocked |
| D4 | G08/G09/G15 shared order, approval, research-account and learning contracts | Engineer; owner reviews unresolved business rules |
| D5 | Publish revised goal-by-goal estimates, parallel dependencies, contingency and trial-entry forecast | Engineer and owner; unresolved external gaps remain explicit |

D5 is the deadline to **publish what is known and blocked**, not a guarantee that providers answered or the exhaustive audit finished. On D10 review actual velocity and update the forecast again. Unanswered external dependencies get owner/next-review dates, not invented completion dates. Detailed risk defaults and the implementation slice still require approval.

After the trial-entry gate, observation lasts at least 30 elapsed calendar days and 20 actual exchange sessions, whichever is longer. Each final prediction still needs its own outcome window: a final 60-session prediction needs 60 trading sessions from its defined entry, not 60 calendar days. Operational trial completion and complete multi-horizon validation are separate milestones. No live launch or guaranteed model-improvement date is promised.

Daily routine on days worked:

1. Select bounded subitems and expected acceptance evidence before coding; record blockers and the single active implementation lane.
2. Implement only authorized scope; run relevant offline tests. Runtime/model work runs on the spare laptop.
3. Record actual results, timings and failures in [daily progress](daily-progress.md). Update only evidence-earned checkpoints here.
4. Commit/push verified scoped work with relevant docs and the current diagram when changed; give a safe spare-laptop script for that milestone.
5. Re-estimate weekly from completed subitems and unresolved dependencies. Do not turn a deadline into permission to lower quality gates.

Next decision: approve detailed risk/fill rules and the initial evidence/implementation work slice including G13/G14 feasibility. The owner has accepted the parent goals and alignment clarifications. **That documentation approval does not silently authorize application implementation or any broker transaction.**
