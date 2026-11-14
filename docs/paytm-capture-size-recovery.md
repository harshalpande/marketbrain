# E246: diagnostic report-size correction

**Follow-up:** The owner reports no saved JSON is available. Use `GetPaytmTlsCaptureState.ps1 -CurrentStateOnly`; this needs no historical file. The collector now reads current state first and also tolerates an empty checkpoint directory. Five local collector workflows pass. Historical cleanup remains unverified until the current-state report is reviewed.

November14,2026: owner console shows43 ready samples, zero sampled outages and228/300 seconds, then SESSION_REPORT_TOO_LARGE. This is a reproduced collector bug: full worker snapshots were repeated in every sample and exceeded the existing64KiB atomic report limit. The previous tests used small worker fixtures and did not test the real serialization budget. These observations are encouraging but do not complete the diagnostic or prove uninterrupted connectivity or final cleanup.

## Fix

Samples now contain only sequence/time/state, attempt/failure counters, HTTP status and TLS summary values. At most64 samples are retained; a dropped-sample counter makes truncation visible. Full sanitized first/latest observations remain separately available. The shared64KiB writer bound is unchanged. If final serialization fails for another reason, a separate small `.final.json` records cleanup/stop outcomes and references the preserved checkpoint; the run remains REVIEW_REQUIRED.

Regression verification reproduces the old overflow using the supplied realistic prior recovery receipt, then performs200 real atomic writes with full failure evidence. The resulting report is35,274 bytes, including64 retained samples and first/latest observations. Seven fake-clock capture workflows pass; nine controller workflows/50 assertions include forced final serialization overflow and verified cleanup/fallback. Three read-only collector workflows cover explicit/automatic checkpoint selection, wrong-mode refusal and preservation of the source checkpoint. These are local tests; spare-laptop state remains unverified.

## Next action: read current state, do not replay installation

The old console exception happened after diagnostic installation/start. A previous atomic checkpoint may exist, but the owner reports none available; do not assume one survived or infer final stop from console output. Repeating `-TlsPhaseDiagnostic` would target the wrong prior worker identity. Use this read-only state collector first. With -CurrentStateOnly it reads current worker/task/controls without requiring any prior report. Optional checkpoint mode summarizes a diagnostic receipt when available. It does not start/stop/reset the gateway, change keys, access the broker or change application state. Output is one small JSON.

Run **PowerShell7 as Administrator** on the spare laptop (no PuTTY or Docker rebuild needed):

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7.' }
Set-Location 'C:\Users\Harshal S Pande\Documents\workspace\marketbrain'
$changes = @(git status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git status failed.' }
if ($changes.Count) { throw 'Preserve local changes before pulling.' }
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed.' }
& '.\ops\windows\GetPaytmTlsCaptureState.ps1' -CurrentStateOnly
```

Expected `TLS_CAPTURE_STATE_COLLECTED_REVIEW_REQUIRED`. Share the printed `paytm-tls-capture-state-*.json`. If automatic selection refuses a newer unrelated checkpoint, pass `-CheckpointPath` with the exact interrupted diagnostic file; do not delete other reports. The old checkpoint is never rewritten. Its cleanup flags are historical checkpoint values, not current proof. Use the separate current-state evidence for the next recovery decision.

After reviewing the exact current worker and task state, prepare a matching recovery/observation handoff; no automatic stale-receipt reset. G1/G2 remain100%, G3 40%, G4–G6 0%;12/30 (40%) bounded readiness, no new acceptance.
