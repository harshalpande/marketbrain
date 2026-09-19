# Two-track evidence engineering (E69)

2026-09-19. Owner authorized proceeding after the two-track preparation documentation. This batch implements the **evidence infrastructure**, not a live collector or market-trained predictor. It advances G02 preparation and G10 recovery support; it does not earn a whole-goal checkpoint or raise forecast accuracy.

## Delivered together

| Subgoal | Implemented behavior | Remaining boundary |
|---|---|---|
| A: preserve and assess existing history | Read the exact accepted E65 snapshot; verify its SHA256/E52 binding, 600 identities, 150 dates, four symbols, ten numeric features and retained blockers | No new mapping, acquisition, feature calculation or market fit. Point-in-time eligibility stays 0; retrospective fitting eligibility remains unassessed |
| B: prospective record storage foundation | Versioned, append-only, hash-chained disk records; source/universe/calculator/calendar identities; distinct event/receipt/decision/input-availability times; explicit policy limits | Standalone internal Java component, **not connected** to a provider, scheduler, endpoint, DB, prediction engine or notification system |
| B: quality and revision handling | Missing, stale, future, impossible-order or clock-untrusted data quarantined; unknown availability never manufactured; duplicates do not write; conflicts remain visible; corrections reference the original decision | Declared metadata and hashes do not prove provider authenticity, price adjustment, rights, historical availability or permission to train |
| B: persistence and recovery | Cooperating-writer lock; bounded records/bytes; per-frame hashes and chain validation; forced data-file writes; partial-tail recovery to a new destination only | Original damaged store untouched. No automatic recovery of checksum corruption or incomplete headers. No hardware power-loss or backup/restore certification |
| Combined evidence handoff | One compact JSON with input assessment, embedded synthetic ledger bytes, checks, raw stdout/stderr, hashes, timings, progress and failure detail | Spare PS7/JDK verification pending; complete JVM output can be reviewed again without executing Java |

Implementation: `NumericalEvidenceLedger.java`; `NumericalEvidenceLayer.ps1`; `TestNumericalEvidenceLayerBundle.ps1`. No Spring bean, constructor, property binding, dependency, migration or startup path changed. CLI accepts only `--synthetic-evidence`; it cannot collect or fit arbitrary market data. The runner requires a native JDK 21+ (the accepted spare environment already reported Java25); no Docker rebuild, restart or automatic download.

The synthetic CLI creates private temporary fixture stores and deletes only its explicitly named fixture files after embedding the ledger in the result. The production-facing internal store does not delete or overwrite existing records. `evidence.bin` and a coordination lock are the two store files; an explicit recovery adds a receipt in a new store. Hash chains detect accidental corruption/order changes, **not malicious complete rewriting**; external anchoring, authenticated source evidence, permissions, retention and backup policy are still needed for operational use. The bounded prototype audits the file before each append, rather than claiming high-throughput Nifty500 readiness.

The fixture uses a 60-second age limit, 1000-ms skew bound, 30-record cap and 128-KiB cap solely to exercise boundaries. These are **not operational defaults**. The approved preparation JSON remains a historical planning artifact: capture settings and collection/fit authorizations stay unset/false. This document records the new store implementation without pretending that its collector is implemented. Raw payloads, outcome targets, forecasts and credentials are not stored by this component; raw-input references are hashes. Forecast and matured-outcome stores remain separate future work.

## Verification and acceptance

- 387 standard Java tests and Maven package passed locally; 17 new JUnit cases, including byte-prefix preservation, canonical identities, time boundaries, old events with fresh receipts, policy mismatch, frame reordering, and partial-frame recovery.
- 22 fixed embedded persistence checks passed. The PowerShell reviewer independently recomputes file/frame/snapshot/recovery hashes and verifies record sequence, prior hashes, dispositions and safety flags.
- 35 PowerShell 5.1 workflow assertions passed: full bundle, input unchanged, safety mutations, corrupted ledger, correction/recovery binding, completed-result replay, changed implementation rejection, failure checkpoint and missing/unapproved snapshot rejection. Local full bundle sample 4.51 seconds; replay 0.98 seconds. Not a spare-laptop time guarantee.
- No application service, database, Docker, provider, LLM, notification or trading execution was used for this verification. Prior accepted E65/E68 spare checkpoints are not rerun. Ordinary local regression tests still include existing synthetic test coverage.
- [Persisted local verification](evidence/numerical-evidence-layer-local-review-20260919.json). Spare acceptance is a new, bounded evidence-store check, not another round of model tuning. Share only `numerical-evidence-layer-*.json`.

## Spare command after a clean fast-forward pull

```powershell
$parameters = @{
    SavedMappingReportPath = 'C:\MarketBrainData\Review\numerical-research-mapping-20260919-173811-99db869b03af.json'
    OutputDirectory       = 'C:\MarketBrainData\Review'
    TimeoutSeconds        = 120
}
& '.\ops\windows\TestNumericalEvidenceLayerBundle.ps1' @parameters
```

If the accepted mapping was moved, supply its existing full path. A wrong hash stops the operation; do not recollect data to solve a missing-file problem. For a reporting failure **after** successful JVM completion, rerun with the same parameters plus `-ResumeReport '<existing bundle path>'`; saved implementation hashes must match. Incomplete JVM output requires investigating the preserved failure before a new short run. No retry loop is added.

## Next grouped milestone

After accepting the spare evidence, close E69 and avoid repeating it. Prepare the operational capture plan (allowed source/rights, exact input fields and frequency, timestamp semantics, freshness/skew limits, quotas/retention/backups) together with the retrospective scope/evaluation decision. Wire a bounded collector only after that scope is approved. Upstox price/action clarification remains **PENDING_EXTERNAL_REPLY**; neither this store nor an owner scope choice resolves it. Market-fit eligibility, final evaluation thresholds and explicit fit release remain separate gates. No deadline or percentage of stock-prediction success is claimed.
