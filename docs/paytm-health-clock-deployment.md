# Restricted Java clock deployment

E292 accepts this deployment in 210.824 seconds. Continue with [scheduled collector integration](paytm-health-collector-batch.md); no repeat rebuild is required.

E291 accepts the combined scheduled clock/token test in 54.449 seconds. Eleven source hashes match 950f392; the exact non-admin health account ran in session 0, signed, read the VPS clock, decrypted its token and authenticated locally. The temporary task was removed and batch policy was unchanged.

The collector must compare Java time with VPS time without using the broader paper-account read credential. This service update adds `POST /api/v1/paytm/route-health/clock`, authenticated only by the existing diagnostic health token and the existing loopback Host/header restrictions. Its empty-body response contains `HEALTH_CLOCK_V1`, boot ID, numeric `observedEpochMillis`, accepted=false and ordersEnabled=false, with no-store caching. Epoch milliseconds avoid PowerShell version-dependent automatic parsing of ISO strings.

Clock reads do not issue/consume a health challenge, publish health, call the broker or arm the route. This is a Java clock sample, not proof of NTP synchronization or acceptable offset; the future collector must compute and enforce bounds using live VPS/Windows observations.

## One deployment and verification batch

The existing deployment controller now has an explicit clock-upgrade mode:

1. Bind to the accepted scheduled receipt and current locked application boot. Verify local Docker, clean source, writer lock, account snapshot, existing token, rollback image and packaged/source migration equality. Stop on baseline drift.
2. Preserve the existing diagnostic token, container settings, mounts and account. Build the new service image while the current service runs. No token rotation or custody reinstall.
3. Recreate only MarketBrain, verify settings and locked state, run existing authentication/unhealthy/replay/expiry checks, then check clock receipt, preservation of an outstanding challenge, rejection of the paper-read token and rejection of a request body.
4. Restart once; verify a new boot, clock endpoint again, rejection of old-boot evidence, unchanged account and writer/route locks. Failed deployment attempts use the existing ownership-checked rollback path and preserve the old token/image. No database migration change is included.

Alerts briefly pause during recreation and restart. No collector is installed and no healthy evidence is published by this batch. Keep the gateway and existing services available; do not run concurrent deployment or paper-review work during it.

## Spare laptop

Use PowerShell 7 as Administrator, with Docker Desktop and MarketBrain running. Update clean main and run:

```powershell
& '.\ops\windows\ActivatePaytmHealthBridge.ps1' `
    -ClockUpgradeReport 'C:\MarketBrainData\Review\paytm-health-scheduled-c0e9c9334c0d457c87cb31ec92a97d48.json'
```

No PuTTY, SSH passphrase or token entry is required. Allow the Docker build to finish; the controller displays stage progress and records bounded command timings. Expected `HEALTH_CLOCK_DEPLOYED_LOCKED_COLLECTOR_PENDING`. Share the one `paytm-health-activation-<run>.json`. If it fails, retain the report and rollback images; do not rerun blindly or prune containers/images.

## Validation and remaining work

27 Java tests pass across health bridge and application route, including Spring defaults/wiring, clock authentication and request restrictions, challenge preservation and absence of transport authority. 17 PowerShell fixtures pass, covering actual boundary helper behavior and both initial activation and upgrade flows: success, build/deploy/boundary failures, ownership-blocked rollback, token preservation and environment restoration. These fixtures do not deploy the spare service; the runtime report establishes that acceptance.

G3 remains 4/5 (80%), overall Paytm readiness 14/30 (46.7%). Next: connect the unattended collector using restricted clock/token access, then combined startup/logoff, stale-clock, loss/recovery and no-direct-fallback acceptance. This update does not establish broker login, quote collection or order readiness.
