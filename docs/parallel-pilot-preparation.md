# Parallel numerical and paper preparation — E72

2026-09-19. Owner authorized parallel progress. This batch prepares three independent lanes; it does not approve draft operational defaults or activate connected execution.

| Lane | Delivered | Next gate |
|---|---|---|
| G02/G03 numerical preparation | Versioned daily-capture/evaluation proposal and fail-closed consistency validator | Owner/source review; session-aware capture adapter and explicit release; eligible data before fitting |
| G08 paper foundation | Standalone exact-paise INR100,000 account, reservations, partial fills, cancellations, expiry, duplicate protection and independently reconciled audit | Durable transactions/recovery, realistic execution and risk policies, authenticated approval, P&L and portal integration |
| G01/G04/G05/G06 provider readiness | Official-reference and existing-code review, separating reusable connectors from missing capabilities | Upstox source reply, account/rights evidence, streaming integration and governed news budget/entity handling |

## Accepted work stays closed

E71 records 22/22 successful spare evidence-store checks in 4.254 seconds. E65 mapping and E68 learner engineering also remain accepted. Do not recollect history, rerun inference or repeat these suites. The new runner exercises only the new paper fixtures and draft-policy consistency.

The existing snapshot remains 600 rows over 150 dates/four stocks, with zero point-in-time training-eligible rows and unassessed retrospective eligibility. Source adjustment/action semantics, data rights and historical availability remain unresolved. The Upstox request is PENDING_EXTERNAL_REPLY. The policy's proposed final evaluation requires substantially more eligible dates and an untouched final set; this draft is not a claim that current data satisfies it.

## Verification and boundaries

- Full Maven package: 410 tests, no failures/errors/skips, including 20 new paper JUnit tests.
- Paper source-launch suite: 26/26 fixed checks; independent PowerShell recomputes cash, fees, holdings, reservations and order transitions from the journal.
- Draft policy: 29 consistency checks plus 18 unsafe mutations rejected without changing source files.
- Combined workflow: 32 assertions, including completed-output replay without another JVM and rejection of altered manifests/results.
- Peer review caught and corrected risk timestamps predating the executable quote, missing cancellation/expiry audit events, and a retention-window mismatch in the draft. These fixes are covered by tests or explicit policy prerequisites.

The new core is in-memory, not a Spring bean/API or database migration. It cannot provide restart durability or an activated paper account. Fixture risk/fee/freshness limits are not approved production settings. All provider, model, database, notification and real order actions remain disabled. Synthetic order/fill counters are separately reported rather than hidden behind zero external-action counters.

The combined runner saves a unique compact JSON containing policy, checks, stdout/stderr, source hashes, timing, progress and failure checkpoints. Timeout defaults to 120 seconds; source launch took about four seconds locally, not a spare-runtime guarantee. Completed JVM output may be rechecked using `-ResumeReport` only when the implementation manifest and raw output hash match. Preserve failed reports; do not retry an unchanged failure blindly.

## Spare handoff

After a clean fast-forward pull, use native JDK21+ and PowerShell5.1+:

```powershell
& '.\ops\windows\TestNumericalPaperPreparationBundle.ps1' -OutputDirectory 'C:\MarketBrainData\Review' -TimeoutSeconds 120
```

Expected status: `PREPARATION_CHECKS_PASSED_RUNTIME_RELEASE_BLOCKED`. Share the one printed `numerical-paper-preparation-*.json`. No Docker rebuild, service restart, account credentials, model download or original mapping-file selection is required.

## Next grouped decisions and implementation

Review [capture/evaluation proposals](numerical-pilot-policy-proposal.md) as two grouped decisions, including frequency, quotas, rights/retention and the conservative acceptance bar. Approval is not inferred from a passing validator. Separately freeze the paper persistence/approval/fill contract before wiring the new core to the existing schema, whose one-fill-per-order constraint cannot support this partial-fill lifecycle unchanged. These preparations may proceed alongside the pending source reply; an affected data gate is never bypassed.

Overall paper-first completion remains **12.4%** under the roadmap's whole-goal checkpoints. This batch is measurable component progress, not predictive accuracy or completed full goals. Spare verification of E72 is pending; no claim of runtime acceptance is made from local tests.
