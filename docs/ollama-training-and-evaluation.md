# Ollama training, rubric and evaluation design

Status: Step 78 Java-governed arbitration with Granite as bounded reviewer.

MarketBrain does not use Ollama as a generic chatbot. Ollama is treated as a local research assistant that must be
guided by a versioned MarketBrain playbook, labelled positive and negative examples, a scoring rubric, and strict
response guardrails.

## Training approach

The first governed approach is instruction/RAG-style training rather than permanent model fine-tuning. Each Ollama
ranking request includes:

- a feature dictionary and interpretation playbook;
- positive labelled examples from the immutable prototype dataset;
- negative labelled examples from the same dataset;
- benchmark-laggard and drawdown-trap examples from the same dataset;
- interaction rules for trend, momentum, participation, volatility, benchmark excess and drawdown;
- an explicit Java DTO-shaped JSON response contract;
- deterministic Java baseline scores/ranks and signed contribution rules;
- a mandatory research-only, no-signal/no-order boundary.

True fine-tuning can be reviewed later only after enough governed examples and evaluation results exist.

## Metric-level scenarios to teach

| Metric | Positive interpretation | Negative or misleading interpretation |
| --- | --- | --- |
| `daily_return_percent` | Recent momentum if confirmed by trend and volume. | One-day spike can be noise or exhaustion. |
| `sma20/sma50/sma200` | Bullish alignment when short/medium/long trend agree. | Price far above averages with high ATR can be extended. |
| `ema12/ema26` | Short-term momentum when EMA12 leads EMA26. | Weak crossover during poor long-term structure is fragile. |
| `rsi14` | 55-70 can show constructive strength. | Very high RSI plus high range position/ATR can indicate late entry risk. |
| `atr14` and `annualized_volatility20_percent` | Controlled volatility supports cleaner swing setups. | High volatility increases stop distance and drawdown pain. |
| `volume_ratio20` | Above-normal volume confirms participation. | Extreme volume without trend confirmation can be a news spike. |
| `range_position252_percent` | Leadership/breakout context when trend confirms. | Near 100 with high RSI/ATR can be exhaustion. |
| `benchmark_excess_return_percent` | Confirms stock-specific strength beyond the proxy. | Positive absolute return can still be weak if it lags the proxy. |
| `maximum_drawdown_percent` | Lower drawdown for similar return means better quality. | High return with high drawdown is lower-quality evidence. |

## Guardrails

Ollama output is not accepted unless it is valid JSON matching the response schema. Guardrails verify:

- schema version;
- requested horizon;
- exactly one ranked entry per candidate;
- exactly one deterministic `candidateId` per candidate, using `CANDIDATE_001`, `CANDIDATE_002`, etc.;
- symbol copied exactly from the row matching that `candidateId`;
- ranks are unique and complete;
- score is between 0 and 100;
- confidence is `LOW`, `MEDIUM` or `HIGH`;
- every candidate has positive evidence, risk flags, a reason and `notTradingSignal=true`;
- every candidate uses the exact `signedContributions` DTO fields;
- signed contributions are bounded to `-100..100`, while `finalScore` remains `0..100`;
- field-level validation reports the exact failing field and value where practical;
- risk and research-only notes are present.

If the response fails these checks, MarketBrain stores/reports the response as a guarded review failure. It still
creates no signal, paper fill, order or broker action.

## Evaluation layer

Step 68 adds a separate review-only evaluation pass. MarketBrain asks Ollama to rank the same bounded candidate set,
then compares the schema-valid response with the hidden future labels already present in the immutable prototype
dataset.

The evaluation layer checks:

- Ollama top pick versus the actual best 5/20/60-session outcome for the selected horizon;
- whether the actual best candidate appeared in Ollama's top three;
- top-three overlap between Ollama and realised outcomes;
- rank-correlation score across the candidate batch;
- high-confidence misses;
- negative-return names placed in Ollama's top three;
- vague reasoning that does not mention known feature families such as SMA, EMA, RSI, ATR, volume, volatility,
  benchmark excess, return, trend, momentum or drawdown.

The quality review can pass, warn, or report weak ranking quality. It is still not a trading signal. It performs no
database writes and creates no signal, paper fill, order or broker action.

## Score calibration

Step 69 adds score-scale calibration. Ollama may rank candidates correctly while still using unhelpful scores such as
15, 10, 5, 2 and 1. MarketBrain therefore gives Ollama an explicit score rubric:

- `85..100`: exceptional multi-factor setup;
- `70..84`: strong setup;
- `55..69`: constructive watchlist;
- `40..54`: mixed or risky;
- `20..39`: weak;
- `0..19`: avoid or very weak.

The calibration preview runs bounded candidate batches, compares scores with hidden outcomes, and flags:

- compressed score spread;
- underused 0-100 scale;
- actual best candidate receiving a low score;
- top score not belonging to the actual top half;
- negative score-rank correlation;
- high-confidence misses or negative-return names in the top three.
- top score assigned to a negative-return candidate;
- high score or high confidence assigned to a bottom-half realised outcome.

This is still review-only. A weak calibration result means the prompt/rubric needs improvement; it is not a trading
signal and never bypasses the deterministic risk engine.

## Chunked calibrated ranking

Step 70 handles the practical limit first observed with `gemma3:4b`, improved with `qwen3:8b`, and baselined with
`ibm/granite4.1:8b`: larger batches can still stress schema/rank/symbol guardrails. MarketBrain therefore processes
larger candidate sets in smaller lots.

Default behavior:

- process a deterministic symbol-ordered candidate set;
- split into chunks of 4;
- call Ollama once per chunk;
- retry a failed chunk once by default;
- validate schema, ranking quality and score calibration per chunk;
- select a small number of finalists from each accepted chunk;
- merge finalist summaries for human review.

Each chunk records whether it passed, passed with warnings or failed after retries. The final merged result is still a
research artifact only. It creates no signal, paper fill, order or broker action.

Step 71 hardens the chunked flow after observing that some 4-candidate chunks still failed symbol/rank guardrails.
The prompt now gives each candidate a deterministic model-safe ID (`CANDIDATE_001` etc.) and requires Ollama to return
that ID with the copied symbol. Validation now distinguishes candidate-ID failures, symbol-copy mismatches, symbol-set
failures and rank-sequence failures. The PowerShell script writes detailed root-cause records and failed-attempt raw
Ollama responses so the next correction can be based on concrete evidence rather than guessing.

Step 72 adds repair-retry behavior for schema-blocked attempts. Every chunk prompt now includes an exact
`rankedCandidates` skeleton listing the required candidate IDs and symbols. If a guarded attempt fails, the next retry
includes a targeted repair instruction containing the previous guardrail failures and the exact expected row count.
This is designed to repair failures such as `RANKED_CANDIDATE_COUNT` without lowering the chunk size too early.

Step 73 strengthens Granite's outcome-aware rubric. The prompt now explicitly optimizes for forward net return,
benchmark excess and smoother drawdown path, not merely attractive current features. Training examples include
positive winners, negative losers, benchmark-laggard traps and drawdown traps. High confidence is reserved for
exceptional multi-factor candidates with minimal conflicts, and score calibration now flags high-score or
high-confidence misses more explicitly.

Step 74 responds to the first `ibm/granite4.1:8b` total-24/chunk-4 run where all chunks were schema-valid but every
chunk was accepted with weak quality/calibration warnings. The root cause was not JSON structure; it was ranking and
score calibration. Granite over-scored some conflicted or bottom-half outcomes and occasionally gave HIGH confidence
to candidates that later evaluated poorly.

The Step 74 fix works on multiple fronts:

- prompt/rubric: candidate rows now include derived guardrail tags for trend, EMA momentum, RSI zone, volume,
  volatility, range position and a `score_cap_hint`;
- examples: the playbook now adds false-confidence traps and smooth-outperformer examples in addition to winners,
  losers, benchmark laggards and drawdown traps;
- scoring: `HARD_CAP_69`, `SOFT_CAP_84` and `HIGH_ELIGIBLE` are explicitly explained to Granite;
- evaluator: any 85+ score on a bottom-half or negative-return outcome is flagged, not only the single top-score row;
- retry policy: schema-valid but weak quality/calibration chunks are no longer accepted immediately when retries
  remain. They receive a targeted repair prompt first. The final attempt may still be accepted with warnings so review
  can continue, but the warning evidence remains visible.

Step 75 responds to the next Granite run after Step 74. Confidence calibration improved materially: Granite stopped
using HIGH confidence on the reviewed weak candidates, and weak chunks were retried as designed. However, ranking
quality remained weak because Granite still preferred some attractive chart stories over better realised outcomes.
The evidence showed two important patterns:

- recovery-style candidates with low range position, controlled/moderate volatility and acceptable participation can
  outperform even when recent momentum looks weak;
- overextended momentum candidates with hot RSI/range, high volatility and one-day strength can look attractive but
  still become lower-quality choices.

Step 75 therefore adds a non-hidden deterministic feature prior to the prompt. Candidate rows now include
`recovery_tag`, `overextension_tag`, `feature_prior_score` and `feature_prior_bucket`. These values are derived only
from as-of technical features, not future labels. Granite is instructed to use the prior as a starting guardrail, while
still explaining any override. The score-cap system also adds `HARD_CAP_54` for extreme risk/overextension cases.

This still does not convert Ollama output into a trading signal. It remains a governed research/evaluation artifact.

Step 76 responds to the next V4 run. The result still showed no passed chunks: confidence remained safer, but Granite
continued to top-rank some bottom-tier candidates and under-score the actual strongest candidates. The correction moves
beyond prompt prose:

- candidate rows now include deterministic component scores: `trend_score`, `momentum_score`, `participation_score`,
  `risk_penalty`, `recovery_credit`, `overextension_penalty`, `feature_prior_score` and `feature_prior_rank`;
- `feature_prior_rank` is the Java-computed baseline order for the chunk. Granite may override it only with explicit
  feature evidence;
- the response schema now requires each ranked candidate to include a `subScores` object with trend, momentum,
  participation, risk, recovery, overextension and final score values;
- guardrails reject missing or invalid sub-scores and reject a large mismatch between `subScores.finalScore` and the
  candidate's top-level score;
- evaluation ranking now uses an outcome-quality label rather than raw return only:
  `netReturn + 0.5 * benchmarkExcess - 0.25 * maximumDrawdown`, with extra penalties for negative return or benchmark
  lag.

This keeps the governing order intact: Java computes deterministic as-of features and guardrails first; Ollama explains
and ranks within that structure; hidden labels are used only for offline review-quality evaluation.

Step 77 responds to the next V5 run, where most chunks were blocked by `SUBSCORE_RANGE`. The important finding was
that Granite was not merely misbehaving: the contract was internally inconsistent. Java supplied signed factor scores
such as negative trend or momentum contributions, but the response schema required `subScores` in `0..100`.

The Step 77 correction hardens communication with Granite instead of relying on repeated repair attempts:

- the prompt now includes an explicit Java DTO contract (`RankingResponseDto`, `RankedCandidateDto`,
  `SignedContributionsDto`) rather than a loose "return JSON" instruction;
- `subScores` is replaced by `signedContributions`;
- `trendContribution`, `momentumContribution`, `participationContribution`, `riskPenalty`, `recoveryCredit`,
  `overextensionPenalty` and `algorithmAdjustment` are allowed to be signed integers from `-100..100`;
- `finalScore` remains bounded to `0..100` and must stay close to the top-level score;
- input penalties are explicitly converted to negative signed JSON contributions;
- validation failures are more precise, for example identifying the exact signed-contribution field and invalid value;
- each model attempt now carries prompt/response sizes, hashes, elapsed Ollama time and Ollama token-count metadata;
- a Java-owned async job endpoint starts the chunked ranking job and exposes progress while keeping local model
  concurrency fixed at `1` for the current spare-machine hardware.

Repair retry remains only a fallback for malformed or incomplete responses. The intended primary control is now the
algorithm-bound DTO contract plus deterministic Java guardrails.

Step 78 formalizes the Java-vs-model responsibility split.

Java is the deterministic owner for data access, feature calculation, baseline scoring, final arbitration, execution
eligibility, idempotency and all safety guardrails. Granite is a bounded reviewer/challenger. It may rank and explain,
but its output is not accepted as the final governed research order by itself.

The evaluation result now exposes this separation for every candidate:

- Java baseline rank;
- Java baseline score;
- Java baseline bucket;
- Java baseline reason;
- Granite/Ollama rank and score;
- deviation between Granite and Java baseline;
- final Java-governed review rank;
- final Java-governed review score;
- arbitration decision and arbitration reason.

The arbitration policy deliberately keeps Java as the ranking spine:

- if Granite stays within one rank of Java baseline, Java blends a small portion of the model score into the final
  review score;
- if Granite moves more than one rank away without strong feature-specific reasoning, Java holds the baseline;
- if Java score-cap risk applies, Java holds the baseline even when Granite tries to promote the candidate;
- if Granite provides a feature-specific challenge, Java records it but only moderately adjusts the deterministic
  score.

This is the intended long-term pattern for all future model/tool interaction: the model can request, review, explain
and challenge, but Java validates, arbitrates and executes through bounded contracts.

## Daily fresh-data feedback loop

Post-market collection and Telegram/WhatsApp process notifications prove that fresh data is arriving. That fresh data
should eventually strengthen Ollama's training loop, but only after a governed feedback design is implemented:

1. daily technical snapshot is created after market close;
2. the daily snapshot is compared with the current playbook/rubric expectations;
3. later outcomes are attached only after their 5/20/60-session label windows mature;
4. examples are promoted into the playbook only after review;
5. prompt/rubric versions and evaluation results are retained for audit.

The daily data is therefore a validation and feedback source, not an automatic unreviewed model-training stream.
