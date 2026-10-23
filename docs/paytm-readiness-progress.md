# Paytm readiness: evidence-based group percentages

Owner request, 2026-10-23: after **every shared test report**, publish all six group percentages, what advanced, what remains, and the next action. This is now the reporting baseline, not an estimate of effort or a confidence score.

## Measurement rule

The [machine-readable checklist](paytm-readiness-progress.json) fixes **five equally weighted acceptance checkpoints per group**. Each accepted checkpoint contributes20 percentage points within that group. Only reviewed evidence closes a checkpoint. A prepared script, local mock test, intended configuration or successful unrelated group does not close a spare-runtime checkpoint. Do not add/remove checkpoints silently to inflate progress; scope changes require a dated rebaseline and explanation. Percentages describe accepted evidence at review time, not continuous live health or total MarketBrain completion.

## Current accepted snapshot — E185

| Group | Accepted checkpoints | Accepted completion | Remaining |
|---|---:|---:|---|
| G1 VPS maintenance |5/5|100%|No repeat required; host microcode remains explicitly outside guest assurance |
| G2 Unattended gateway |1/5|20%|Windows account/agent, key custody, production supervisor/task, managed VPS lifecycle |
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

The [next account-provisioning step](paytm-gateway-account.md), if successful and reviewed, closes **G2.2**: G2 **20% → 40%**. No other group advances automatically. The script reports the accepted snapshot at its release and marks40% as a candidate, never self-approves its evidence.
