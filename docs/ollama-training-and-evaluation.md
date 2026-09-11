# Ollama training, rubric and evaluation design

Status: Step 72 repair-retry hardening.

MarketBrain does not use Ollama as a generic chatbot. Ollama is treated as a local research assistant that must be
guided by a versioned MarketBrain playbook, labelled positive and negative examples, a scoring rubric, and strict
response guardrails.

## Training approach

The first governed approach is instruction/RAG-style training rather than permanent model fine-tuning. Each Ollama
ranking request includes:

- a feature dictionary and interpretation playbook;
- positive labelled examples from the immutable prototype dataset;
- negative labelled examples from the same dataset;
- interaction rules for trend, momentum, participation, volatility, benchmark excess and drawdown;
- a strict JSON response schema;
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

This is still review-only. A weak calibration result means the prompt/rubric needs improvement; it is not a trading
signal and never bypasses the deterministic risk engine.

## Chunked calibrated ranking

Step 70 handles the practical limit first observed with `gemma3:4b` and improved with `qwen3:8b`: larger batches can
still stress schema/rank/symbol guardrails. MarketBrain therefore processes larger candidate sets in smaller lots.

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

## Daily fresh-data feedback loop

Post-market collection and Telegram/WhatsApp process notifications prove that fresh data is arriving. That fresh data
should eventually strengthen Ollama's training loop, but only after a governed feedback design is implemented:

1. daily technical snapshot is created after market close;
2. the daily snapshot is compared with the current playbook/rubric expectations;
3. later outcomes are attached only after their 5/20/60-session label windows mature;
4. examples are promoted into the playbook only after review;
5. prompt/rubric versions and evaluation results are retained for audit.

The daily data is therefore a validation and feedback source, not an automatic unreviewed model-training stream.
