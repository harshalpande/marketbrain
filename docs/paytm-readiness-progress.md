# Paytm readiness: evidence-based group percentages

Owner request, 2026-10-23: after **every shared test report**, publish all six group percentages, what advanced, what remains, and the next action. This is now the reporting baseline, not an estimate of effort or a confidence score.

## Measurement rule

Latest **E201, 2026-11-02**: retained probe inventory accepted, but task launch remains unproven (267011/not-yet-run, no worker result). Extended [read-only event capture](paytm-scheduled-signing.md) is next. G1/G2/G3/G4/G5/G6 remain **100/60/0/0/0/0**, delta0. E198 remains the accepted runtime baseline; E200 inventory handoff below is historical.

Latest **E200, 2026-11-02**: scheduled-signing attempt blocked by an existing probe before changes. Custody still passes; prior task failure is unknown. [Read-only inspection](paytm-scheduled-signing.md) is the next handoff. No new accepted checkpoint: groups **100/60/0/0/0/0**. E198 remains the accepted runtime baseline.

Current **E198, 2026-11-02**: key-custody runtime accepted. Six completed stages in62.802s; scoped import/removal/reload, wrong-host rejection, correct pinned authentication, staged-copy removal and fresh-process signing passed. Six source hashes match f44ef5e CRLF bytes. **G2.3 closes; G2 rises40% to60% (+20 percentage points).** Next [temporary scheduled-account signing](paytm-scheduled-signing.md) is a prerequisite for G2.4, not a repeat import or another completed checkpoint. Reboot/production-supervisor/server-policy retest remain pending.

Historical E194: actual recovery and exact-account probe accepted. Eight completed stages,46.068s total including owner input,6.497s child probe; three reviewed CRLF source hashes match. G2.2 closed and raised G2 from20% to40%. E198 now supersedes that snapshot with60%. Do not rerun account recovery or key custody.

The [machine-readable checklist](paytm-readiness-progress.json) fixes **five equally weighted acceptance checkpoints per group**. Each accepted checkpoint contributes20 percentage points within that group. Only reviewed evidence closes a checkpoint. A prepared script, local mock test, intended configuration or successful unrelated group does not close a spare-runtime checkpoint. Do not add/remove checkpoints silently to inflate progress; scope changes require a dated rebaseline and explanation. Percentages describe accepted evidence at review time, not continuous live health or total MarketBrain completion.

## Current accepted snapshot — E198

| Group | Accepted checkpoints | Accepted completion | Remaining |
|---|---:|---:|---|
| G1 VPS maintenance |5/5|100%|No repeat required; host microcode remains explicitly outside guest assurance |
| G2 Unattended gateway |3/5|60%|Production supervisor/task, managed VPS lifecycle |
| G3 Real recovery/safe failure |0/5|0%|Installed-system interruption, negatives, stop, logoff/boot, health/no-fallback acceptance |
| G4 Paytm login |0/5|0%|Current auth contract, real login/callback, token custody and lifecycle acceptance |
| G5 Fresh quotes |0/5|0%|Instrument mapping, fresh retrieval, stale/errors, reconnect and application integration |
| G6 Telegram review |0/5|0%|Real review-only ACCEPT, REJECT, expiry, replay and unauthorized cases |

Earlier tunnel/container/application-route evidence remains accepted as prerequisite work. Zeros in G3–G6 mean no checkpoint in this **managed-system acceptance baseline** is closed, not that no supporting code or past tests exist. One complete group out of six remains true; do not equate that count with estimated remaining time.

E185 report passed79 assertions,12 unsafe-configuration cases and31 effective SSH settings in2.335s; all five source hashes matched the reviewed Windows checkout. This closes G2.1. It did not start an agent, import a key, install a task or contact the VPS. Previous foundation engineering was locally verified; its spare acceptance is now confirmed.

## Required reporting format after each test

1. Pass/fail and precise evidence limits, report/run identity and measured elapsed time.
2. Six-group table with accepted checkpoints/percentage and blockers.
3. Changed checkpoint and percentage-point delta; if nothing was accepted, explicitly show no increase.
4. Why the next script is needed, exactly what it changes, and what successful evidence would establish.
5. For authorized implementation: verified commit/push and complete spare commands, one shareable JSON where practical. Never request passwords, tokens or private keys in chat.

Next checkpoint **G2.4**, production supervisor and scheduled startup installed and verified, would move G2 **60% → 80%** after runtime review. The temporary scheduled-signing batch is a prerequisite, not all of G2.4. G2.5 then covers managed VPS lifecycle. Earlier report release-time snapshots are historical; E198 supplies current60% acceptance. No other group advances automatically.
