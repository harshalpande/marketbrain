# Durable diagnostic collector

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
