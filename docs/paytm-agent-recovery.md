# Recovery after successful account signing

Current E237, 2026-11-13: signing report 1d103203c982427caea56d4b0671b0e7 passed. All eight source hashes match 5e5dc61 CRLF. The session-0 account listed its expected key and signed twice without errors/timeouts. Worker elapsed2.662s; whole controller118.905s including interactive input. Temporary task removed; all seven production state hashes preserved. Original agent failure cause remains unknown.

The next script uses the established recovery controller with `-AgentSigningRecovery`. This mode replaces no installed code or keys. It verifies the exact accepted signing report, stopped production task, old process absence, seven state hashes, free transport listener, installation and locked application. It copies and verifies all seven files into a protected `agent-recovery-<runId>` directory. Only after verified copies exist does it remove the three old worker status/failure files and the old session checkpoint. Original report files remain intact. A partial failure stops for review; no automatic retry or rollback is attempted.

It starts the existing gateway once, requires a fresh worker, observes health for30 minutes, checks the application TLS route at the beginning/end, and verifies unchanged paper account plus final application/writer locks. Failure after mutation requests STOP and disables the owned gateway task through the existing failure handler. The old checkpoint is recoverable in the printed archive; it cannot be reused with a replacement worker.

Use PowerShell7 as Administrator, with Docker Desktop and the existing MarketBrain container running. No PuTTY/Pageant, key import, password entry or rebuild is needed. Keep the accepted signing and managed-transport reports in `C:\MarketBrainData\Review`.

```powershell
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 as Administrator.' }
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\RepairPaytmNativeProcess.ps1' -AgentSigningRecovery
```

Allow approximately35 minutes. Keep the laptop awake and connected. Share the one printed `paytm-native-recovery-<runId>.json`; the legacy filename/status comes from the reused controller, and `recoveryMode` identifies this no-code-replacement recovery. Expected status: `NATIVE_RECOVERY_AND_30_MINUTE_OBSERVATION_PASSED`. On REVIEW_REQUIRED, share the report and do not rerun, delete markers or sign out.

After acceptance, establish a fresh Before session baseline, then repeat the sign-out and full shutdown phases. This recovery does not itself close G3.4. Progress remains G1/G2/G3/G4/G5/G6 =100/100/40/0/0/0;12/30 accepted checkpoints (40%). Root HTTP503 remains transport evidence only. Login, quotes and trades are not enabled.

Local validation includes29 recovery assertions using temporary files and mocked task operations, plus the existing controller failure/lock regression. Real spare-laptop recovery and observation remain pending.
