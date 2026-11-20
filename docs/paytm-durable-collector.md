# Durable diagnostic collector

2026-11-20: Sign-out lifecycle implementation prepared. Queued Observe is read-only. Apply verifies the accepted activation, preserves its evidence, starts a bounded ten-minute collector/gateway window, records protected boot/logon/worker identity, and returns READY_FOR_OWNER_SIGNOUT. A subsequent Apply requires the same boot and worker, changed owner logon, advancing accepted samples, fresh status, final revocation and cleanup. Restart is a distinct subsequent stage; not counted by sign-out. Local verification: 11 boundary cases and 12 preparation/resume/cleanup cases. Runtime pending; G3 remains 80%.

2026-11-20: Queued bounded durable activation ACCEPTED (4a2a76b5-afea-42d1-8b49-22c934f69017). Four accepted publications across five cycles after one failed sample; final revocation confirmed, non-admin session 0, application locked, task exit 0. Collector and gateway stopped/disabled; guard removed; no cleanup failure. Execution 86.998s, queue process 88.479s. Initial harness stopped prematurely on BACKOFF; fixed to honor existing two-failure allowance without weakening health thresholds. Underlying first-sample cause was not captured and remains unknown. No manual script/password transfer in this run. Evidence: docs/evidence/durable-activation-accepted-20261120.json. Remaining: restart/sign-out lifecycle acceptance. G1/G2 100%, G3 80%, G4-G6 0%; 14/30=46.7% accepted Paytm checkpoints.

First bounded run 7a70d4a2 failed on one unhealthy sample; worker authenticated in non-admin session 0, then revoked health and stopped cleanly; gateway stopped and guard removed. Sample cause was not retained by the installed worker. Harness now permits the existing bounded BACKOFF contract (one/two failures), never counts failed samples as accepted, and still requires three accepted publications. One exact prior stopped/revoked instance may be archived for a reviewed retry; other incidents remain blocked. Local retry archival includes mismatch and unrevoked rejection tests.

2026-11-20: Bounded durable activation implemented using the existing revision-pinned paytm-denial-recovery queue job (Observe/Apply); historical job revisions retain their original behavior. Preflight verifies accepted installation and gateway; Apply claims one attempt, registers an independent three-minute stop for both tasks, observes at least three accepted publications across advancing samples, then verifies graceful revocation, task exit and gateway cleanup. Failed stops retain the independent guard. No owner password, broker login, route arm or orders. Local: 8 sample and 8 orchestration cases; existing 8 gateway readiness/7 workflow cases and atomic summary tests; PS5 guard parsing. Runtime acceptance pending.

2026-11-20 runtime acceptance: queued job b2c4ce14-b2b8-4660-87f7-004a15d9f43b SUCCEEDED. Installed worker, known_hosts and task XML pins matched; task/control disabled; time snapshot age 0.243 seconds. No runtime started. Evidence: docs/evidence/durable-collector-staging-20261120.json. Next: bounded activation with independent shutdown guard, followed by lifecycle acceptance. G3 remains 80%.

2026-11-20: Automatically collected installation ab47639ee8d74da69a9466c0f59e601e: Windows BATCH credential accepted, durable task staged disabled, worker not started. Added queued read-only verification of pinned worker/host/task XML, disabled control, task identity/settings and fresh time snapshot. Local checks: 9 receipt cases and 2 installed-state drift cases on PS5/PS7. Activation and lifecycle remain pending; G3 stays 80%, total 14/30 checkpoints. Evidence: docs/evidence/durable-collector-install-20261120.json.

The accepted temporary batch e514d3f3a91d4e719ad31fadf66597df passed all five rejection/recovery cases and final revocation. The next install stages MarketBrain-Health-Collector-v1 as a disabled Password-logon startup task under the existing non-admin marketbrain-health SID. Both task and control remain disabled; no gateway start, health publication, broker login or orders occur during installation.

Protected worker, pinned known_hosts and administrator-owned control live in collector-v1. Only status/final reports and an exclusive process lease are writable under collector-work-v1. Existing paths/tasks cause a stop, never overwrite. Windows stores the task registration credential; the installer neither queues nor logs it. Existing encrypted SSH/token custody is reused.

When subsequently activated, each live cycle calls the previously verified collector. Two-second normal spacing and bounded backoff follow; three consecutive failures stop the worker and attempt final health revocation. No silent direct-route fallback, health replay or route arm exists. Failed revocation is reported as unconfirmed; Java TTL remains authoritative. Task scheduler auto-restart is deliberately zero: exhausted failures require reviewed recovery. Boot trigger is installed but disabled until activation. Application reboot requires a new worker to obtain the new boot binding.

The installer pins the accepted report SHA256, checks existing account/key/token custody and current time snapshot, validates the password once locally, creates protected files, and verifies the disabled task. Failed/partial installations are preserved for review; do not rerun or delete them. The installed worker hash, host-file hash and task XML hash are retained for subsequent activation verification.

## Run on the spare laptop

Elevated PowerShell7, paired Windows user. Keep automation running. No PuTTY or Pageant action needed.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location "$env:USERPROFILE\Documents\workspace\marketbrain"
git -c gc.auto=0 pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git update failed.' }
& .\ops\windows\InstallPaytmDurableCollector.ps1
```

Enter the existing Windows marketbrain-health password only at the local prompt. Expected DURABLE_COLLECTOR_STAGED_DISABLED_ACTIVATION_PENDING. Queued time-observer Observe collects protected collector-install-result.json automatically. Staging is not acceptance of long-running health or restart/sign-out behavior. Next: verify staging evidence, implement bounded activation/lifecycle control and run actual background/restart/sign-out/recovery acceptance.

Local verification: seven loop paths (healthy, recovery, rejection limit, exceptions, failed revocation, invalid control, failed status writing); seven task-definition cases; generated PS5 parsing and actual child PS5 disabled-gate exit before network/custody. No real account/scheduler installation was performed on the development laptop.
