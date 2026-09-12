package in.marketbrain.training;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class PrototypeSwingOllamaGuidedRankingPreviewService {

    static final String INSTRUCTION_PACK_VERSION = "MARKETBRAIN_SWING_OLLAMA_INSTRUCTION_PACK_V7";
    static final String RESPONSE_SCHEMA_VERSION = "MARKETBRAIN_OLLAMA_RANKING_RESPONSE_V3";
    static final String RUBRIC_VERSION = "MARKETBRAIN_SWING_RUBRIC_V7";
    private static final int DEFAULT_CANDIDATE_LIMIT = 12;
    private static final int MAXIMUM_CANDIDATE_LIMIT = 25;
    private static final int DEFAULT_RANKING_HORIZON_SESSIONS = 20;

    private final PrototypeSwingTrainingDatasetAuditService auditService;
    private final PrototypeSwingOllamaClient ollamaClient;
    private final JdbcTemplate jdbcTemplate;
    private final ObjectMapper objectMapper;

    public PrototypeSwingOllamaGuidedRankingPreviewService(
            PrototypeSwingTrainingDatasetAuditService auditService,
            PrototypeSwingOllamaClient ollamaClient,
            JdbcTemplate jdbcTemplate,
            ObjectMapper objectMapper
    ) {
        this.auditService = auditService;
        this.ollamaClient = ollamaClient;
        this.jdbcTemplate = jdbcTemplate;
        this.objectMapper = objectMapper;
    }
    public PrototypeSwingOllamaGuidedRankingPreview preview(PrototypeSwingOllamaRankingRequest request) {
        PrototypeSwingOllamaRankingRequest safeRequest = request == null
                ? new PrototypeSwingOllamaRankingRequest(null, null, null, null)
                : request;
        String model = model(safeRequest.model());
        int candidateLimit = candidateLimit(safeRequest.candidateLimit());
        int horizon = horizon(safeRequest.rankingHorizonSessions());
        PrototypeSwingTrainingDatasetAudit audit = auditService.audit(safeRequest.datasetRunId());
        validateAudit(audit);

        List<PrototypeSwingOllamaCandidate> candidates = candidates(audit.datasetRunId(), candidateLimit);
        return previewCandidates(safeRequest, audit, candidates, candidateLimit, model, horizon);
    }

    PrototypeSwingOllamaGuidedRankingPreview previewCandidates(
            PrototypeSwingOllamaRankingRequest request,
            List<PrototypeSwingOllamaCandidate> candidates
    ) {
        PrototypeSwingOllamaRankingRequest safeRequest = request == null
                ? new PrototypeSwingOllamaRankingRequest(null, null, null, null)
                : request;
        String model = model(safeRequest.model());
        int horizon = horizon(safeRequest.rankingHorizonSessions());
        PrototypeSwingTrainingDatasetAudit audit = auditService.audit(safeRequest.datasetRunId());
        validateAudit(audit);
        return previewCandidates(safeRequest, audit, candidates, candidates.size(), model, horizon);
    }

    private PrototypeSwingOllamaGuidedRankingPreview previewCandidates(
            PrototypeSwingOllamaRankingRequest request,
            PrototypeSwingTrainingDatasetAudit audit,
            List<PrototypeSwingOllamaCandidate> candidates,
            int candidateLimit,
            String model,
            int horizon
    ) {
        if (candidates.isEmpty()) {
            throw new IllegalStateException("No labelled prototype candidates are available for guided ranking.");
        }
        Set<String> candidateSymbols = new HashSet<>();
        for (PrototypeSwingOllamaCandidate candidate : candidates) {
            candidateSymbols.add(candidate.symbol());
        }
        List<PrototypeSwingOllamaTrainingExample> examples =
                trainingExamples(audit.datasetRunId(), horizon, candidateSymbols);
        if (examples.size() < 6) {
            throw new IllegalStateException("Not enough positive and negative training examples are available.");
        }

        String playbook = playbook();
        String prompt = prompt(audit, examples, candidates, horizon, playbook, repairInstruction(request.repairInstruction()));
        PrototypeSwingOllamaClient.Generation generation = ollamaClient.generateJsonResult(model, prompt);
        String response = generation.text();
        Validation validation = validateResponse(response, candidates, horizon);
        boolean schemaValid = validation.failures().isEmpty();

        return new PrototypeSwingOllamaGuidedRankingPreview(
                schemaValid ? "REVIEW_REQUIRED" : "REVIEW_BLOCKED",
                audit.datasetRunId(),
                audit.datasetContractVersion(),
                audit.sourceUniverseCode(),
                audit.asOf(),
                audit.labelThrough(),
                audit.datasetManifestHash(),
                model,
                candidateLimit,
                candidates.size(),
                examples.size(),
                horizon,
                INSTRUCTION_PACK_VERSION,
                RESPONSE_SCHEMA_VERSION,
                RUBRIC_VERSION,
                sha256(playbook),
                sha256(prompt),
                sha256(response),
                prompt,
                response,
                prompt.length(),
                response.length(),
                generation.elapsedMillis(),
                generation.ollamaTotalDurationNanos(),
                generation.promptEvalCount(),
                generation.evalCount(),
                examples,
                candidates,
                validation.parseableJson(),
                schemaValid,
                validation.failures(),
                true,
                false,
                audit.survivorshipRiskPresent(),
                audit.prototypeTrainingEligible(),
                audit.benchmarkTrainingEligible(),
                audit.pointInTimeSafe(),
                audit.futureLabelsSeparated(),
                false,
                1,
                0,
                0,
                false,
                "Guided Ollama ranking preview used the MarketBrain playbook, labelled examples, "
                        + "strict JSON response schema, and guardrail validation. Daily fresh-data feedback "
                        + "loop is designed but not yet used for training."
        );
    }

    private void validateAudit(PrototypeSwingTrainingDatasetAudit audit) {
        if (!"REVIEW_REQUIRED".equals(audit.status())
                || !audit.auditReadyForOllamaRanking()
                || !"PROTOTYPE_SWING_TRAINING_DATASET_V1".equals(audit.datasetContractVersion())
                || !"CURRENT_SNAPSHOT_PROTOTYPE".equals(audit.sourceUniverseCode())
                || !audit.survivorshipRiskPresent()
                || !audit.prototypeTrainingEligible()
                || audit.benchmarkTrainingEligible()
                || !audit.pointInTimeSafe()
                || !audit.futureLabelsSeparated()
                || audit.databaseWritesPerformed()
                || audit.ollamaCallCount() != 0
                || audit.signalsCreated() != 0
                || audit.ordersCreated() != 0
                || !audit.failedCheckpoints().isEmpty()) {
            throw new IllegalStateException("The prototype dataset audit is not ready for guided Ollama ranking.");
        }
    }

    List<PrototypeSwingOllamaCandidate> candidates(UUID runId, int offset, int limit) {
        return jdbcTemplate.query("""
                SELECT item.symbol, item.effective_as_of, item.latest_close,
                       item.daily_return_percent, item.sma20, item.sma50, item.sma200,
                       item.ema12, item.ema26, item.rsi14, item.atr14,
                       item.annualized_volatility20_percent, item.volume_ratio20,
                       item.range_position252_percent,
                       label5.net_return_percent AS net_return_5,
                       label20.net_return_percent AS net_return_20,
                       label60.net_return_percent AS net_return_60,
                       label5.benchmark_excess_return_percent AS benchmark_excess_5,
                       label20.benchmark_excess_return_percent AS benchmark_excess_20,
                       label60.benchmark_excess_return_percent AS benchmark_excess_60,
                       label5.maximum_drawdown_percent AS maximum_drawdown_5,
                       label20.maximum_drawdown_percent AS maximum_drawdown_20,
                       label60.maximum_drawdown_percent AS maximum_drawdown_60
                FROM prototype_swing_training_dataset_item item
                JOIN prototype_swing_training_dataset_label label5
                  ON label5.item_id = item.id AND label5.horizon_sessions = 5
                JOIN prototype_swing_training_dataset_label label20
                  ON label20.item_id = item.id AND label20.horizon_sessions = 20
                JOIN prototype_swing_training_dataset_label label60
                  ON label60.item_id = item.id AND label60.horizon_sessions = 60
                WHERE item.run_id = ? AND item.classification = 'LABELED'
                ORDER BY item.symbol
                LIMIT ?
                OFFSET ?
                """, (resultSet, row) -> new PrototypeSwingOllamaCandidate(
                        resultSet.getString("symbol"),
                        resultSet.getObject("effective_as_of", LocalDate.class),
                        resultSet.getBigDecimal("latest_close"),
                        resultSet.getBigDecimal("daily_return_percent"),
                        resultSet.getBigDecimal("sma20"),
                        resultSet.getBigDecimal("sma50"),
                        resultSet.getBigDecimal("sma200"),
                        resultSet.getBigDecimal("ema12"),
                        resultSet.getBigDecimal("ema26"),
                        resultSet.getBigDecimal("rsi14"),
                        resultSet.getBigDecimal("atr14"),
                        resultSet.getBigDecimal("annualized_volatility20_percent"),
                        resultSet.getBigDecimal("volume_ratio20"),
                        resultSet.getBigDecimal("range_position252_percent"),
                        resultSet.getBigDecimal("net_return_5"),
                        resultSet.getBigDecimal("net_return_20"),
                        resultSet.getBigDecimal("net_return_60"),
                        resultSet.getBigDecimal("benchmark_excess_5"),
                        resultSet.getBigDecimal("benchmark_excess_20"),
                        resultSet.getBigDecimal("benchmark_excess_60"),
                        resultSet.getBigDecimal("maximum_drawdown_5"),
                        resultSet.getBigDecimal("maximum_drawdown_20"),
                        resultSet.getBigDecimal("maximum_drawdown_60")), runId, limit, offset);
    }

    private List<PrototypeSwingOllamaCandidate> candidates(UUID runId, int limit) {
        return candidates(runId, 0, limit);
    }

    private List<PrototypeSwingOllamaTrainingExample> trainingExamples(
            UUID runId,
            int horizon,
            Set<String> excludedSymbols
    ) {
        List<PrototypeSwingOllamaTrainingExample> examples = new ArrayList<>();
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "POSITIVE_WINNER",
                "label.net_return_percent DESC, label.benchmark_excess_return_percent DESC", 4,
                "Strong labelled winner: learn confluence that produced high net return and positive benchmark excess.",
                "label.net_return_percent > 0 AND label.benchmark_excess_return_percent > 0"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "NEGATIVE_LOSER",
                "label.net_return_percent ASC, label.benchmark_excess_return_percent ASC", 4,
                "Labelled loser: weak future return or benchmark lag should reduce rank even if one feature looks attractive.",
                "label.net_return_percent < 0 OR label.benchmark_excess_return_percent < 0"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "BENCHMARK_LAGGARD_TRAP",
                "label.benchmark_excess_return_percent ASC, item.daily_return_percent DESC", 2,
                "Trap example: do not over-rank candidates that may rise but lag the benchmark or equal-weight proxy.",
                "label.benchmark_excess_return_percent < 0"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "DRAWDOWN_TRAP",
                "label.maximum_drawdown_percent DESC, label.net_return_percent ASC", 2,
                "Trap example: high pain/drawdown or unstable path must cap confidence and score.",
                "label.maximum_drawdown_percent >= 10"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "FALSE_CONFIDENCE_TRAP",
                "item.annualized_volatility20_percent DESC, item.volume_ratio20 ASC", 2,
                "Trap example: do not assign HIGH confidence when volatility is high, participation is weak, or evidence is conflicted.",
                "label.net_return_percent <= 5 OR label.benchmark_excess_return_percent <= 0"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "SMOOTH_OUTPERFORMER",
                "label.benchmark_excess_return_percent DESC, label.maximum_drawdown_percent ASC", 2,
                "Preferred pattern: positive benchmark excess with manageable drawdown deserves a better rank than a noisy chart.",
                "label.net_return_percent > 0 AND label.benchmark_excess_return_percent > 0 AND label.maximum_drawdown_percent < 6"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "RECOVERY_OUTPERFORMER",
                "label.benchmark_excess_return_percent DESC, item.annualized_volatility20_percent ASC", 2,
                "Recovery winner: low range position or weak recent momentum can still be attractive when volatility is controlled and participation is not broken.",
                "item.range_position252_percent < 40 AND label.net_return_percent > 0 AND label.benchmark_excess_return_percent > 0"));
        examples.addAll(trainingExamples(runId, horizon, excludedSymbols, "OVEREXTENDED_MOMENTUM_TRAP",
                "item.range_position252_percent DESC, item.annualized_volatility20_percent DESC", 2,
                "Overextended trap: high daily return, hot RSI/range and high volatility should cap score even when the chart looks exciting.",
                "item.range_position252_percent > 90 AND item.rsi14 > 65 AND item.annualized_volatility20_percent > 35"));
        return List.copyOf(examples);
    }

    private List<PrototypeSwingOllamaTrainingExample> trainingExamples(
            UUID runId,
            int horizon,
            Set<String> excludedSymbols,
            String scenarioType,
            String orderExpression,
            int limit,
            String teachingPoint,
            String additionalCondition
    ) {
        String excludedPlaceholders = String.join(", ", java.util.Collections.nCopies(excludedSymbols.size(), "?"));
        String sql = """
                SELECT item.symbol, item.daily_return_percent, item.sma20, item.sma50, item.sma200,
                       item.rsi14, item.atr14, item.annualized_volatility20_percent,
                       item.volume_ratio20, item.range_position252_percent,
                       label.net_return_percent, label.benchmark_excess_return_percent,
                       label.maximum_drawdown_percent
                FROM prototype_swing_training_dataset_item item
                JOIN prototype_swing_training_dataset_label label ON label.item_id = item.id
                WHERE item.run_id = ?
                  AND item.classification = 'LABELED'
                  AND label.horizon_sessions = ?
                  AND item.symbol NOT IN (%s)
                  AND (%s)
                ORDER BY %s, item.symbol
                LIMIT ?
                """.formatted(excludedPlaceholders, additionalCondition, orderExpression);
        List<Object> parameters = new ArrayList<>();
        parameters.add(runId);
        parameters.add(horizon);
        parameters.addAll(excludedSymbols);
        parameters.add(limit);
        return jdbcTemplate.query(sql, (resultSet, row) -> new PrototypeSwingOllamaTrainingExample(
                        scenarioType,
                        resultSet.getString("symbol"),
                        resultSet.getBigDecimal("daily_return_percent"),
                        resultSet.getBigDecimal("sma20"),
                        resultSet.getBigDecimal("sma50"),
                        resultSet.getBigDecimal("sma200"),
                        resultSet.getBigDecimal("rsi14"),
                        resultSet.getBigDecimal("atr14"),
                        resultSet.getBigDecimal("annualized_volatility20_percent"),
                        resultSet.getBigDecimal("volume_ratio20"),
                        resultSet.getBigDecimal("range_position252_percent"),
                        resultSet.getBigDecimal("net_return_percent"),
                        resultSet.getBigDecimal("benchmark_excess_return_percent"),
                        resultSet.getBigDecimal("maximum_drawdown_percent"),
                        teachingPoint),
                parameters.toArray());
    }

    private String playbook() {
        return """
                MarketBrain swing-ranking playbook:
                - Objective: rank candidates for forward net return AND benchmark excess while avoiding candidates that create avoidable drawdown pain.
                - Never treat one metric as decisive. Rank by confluence of trend, momentum, participation, volatility, and risk.
                - daily_return_pct: positive can indicate momentum, but a one-day spike without trend/volume support is noise. Negative can be pullback or breakdown; interpret with SMA/EMA context.
                - SMA20/SMA50/SMA200: bullish structure improves when price is above rising short and medium averages and SMA20 >= SMA50 >= SMA200. Price far above SMA20 with high ATR can be overextended.
                - EMA12/EMA26: EMA12 above EMA26 supports short-term momentum. A tiny crossover during weak SMA structure is a false-positive risk.
                - RSI14: 55-70 can indicate strength. Above 70 can be exhaustion if range_position252 and ATR are high. Below 45 is usually weak unless other recovery evidence is strong.
                - ATR14 and volatility20_pct: high values imply wider stops and higher pain. High return with high drawdown is lower quality than smoother return.
                - volume_ratio20: above 1.2 can confirm participation. Below 0.8 is weak participation unless other evidence is exceptional. Extreme volume without trend confirmation may be a news spike or exhaustion.
                - range_position252_pct: high values can show leadership or breakout, but near 100 with high RSI/ATR may be late. Low values can be value/recovery only if momentum confirms.
                - benchmark_excess_return is the test of whether the stock added value beyond the equal-weight proxy. A candidate can have positive absolute return and still be a poor pick if it lags the proxy.
                - maximum_drawdown is a pain/risk measure. Penalize candidates where return came with large drawdown; never use HIGH confidence when volatility/drawdown risk is meaningfully unresolved.
                - Prefer balanced setups: positive/repairing trend, controlled volatility, constructive RSI, confirmed volume, and manageable drawdown risk.
                - High confidence requires broad confluence: trend alignment, constructive RSI, participation, not-overextended range position, controlled volatility and no major conflict.
                - Granite calibration rule: if evidence is mixed, cap score at 84 and confidence at MEDIUM. If two or more major conflicts exist, cap score at 69 and confidence at LOW/MEDIUM.
                - Major conflicts include: weak volume (<0.8), high volatility (>35), price below SMA20/SMA50, EMA12 below EMA26, RSI below 45, range_position252 above 90 with high RSI/volatility, or obvious one-day spike risk.
                - A 85+ score must read like a clean winner: trend, EMA, RSI, participation, range and volatility must mostly agree. If you need to explain several caveats, the candidate is not 85+.
                - For each chunk, separate "best chart story" from "best expected outcome". A stock can look interesting and still deserve a lower score if the risk-adjusted/benchmark-excess setup is weaker than peers.
                - Recovery setups: low range position, controlled/moderate volatility and non-broken participation can be valid even when recent daily return or RSI is weak. Do not automatically rank them last.
                - Overextended momentum traps: high daily return, hot RSI, near-100 range position and high volatility are not automatically good. They often deserve MEDIUM/LOW confidence and capped scores.
                - Feature prior score is not a hidden label and is not a trading signal. Treat it as a guardrail prior: strong evidence may override it, but explain why.
                - Feature prior rank is the deterministic MarketBrain baseline rank for this chunk. Use it as the starting order, not as an optional note.
                - If you place a candidate more than one position away from feature_prior_rank, explain the exact feature reason in its reason field.
                - Do not rank a low-prior candidate first unless every higher-prior candidate has severe risk tags or the low-prior candidate is a recovery setup with controlled volatility.
                - Penalize false positives: one-day strength, high score despite weak volume, high score despite negative benchmark-excess-like pattern, high score despite high volatility/drawdown-like pattern.
                - Top rank should be reserved for the candidate with the strongest total package, not merely the highest daily return or highest price strength.
                - Reject contradictory reasoning. If a number is negative, do not call it positive. If volatility is high, do not call risk low.
                - Communication contract: follow the exact JSON DTO supplied in the prompt. Do not rename fields. Do not add wrapper text.
                - Responsibility boundary: Java owns calculations, deterministic baseline ranking, final arbitration, execution and guardrails. Granite is a bounded reviewer that may challenge Java's baseline only with feature-specific evidence.
                - This is prototype research only. Never create or imply a live trading signal.
                """;
    }

    private String prompt(
            PrototypeSwingTrainingDatasetAudit audit,
            List<PrototypeSwingOllamaTrainingExample> examples,
            List<PrototypeSwingOllamaCandidate> candidates,
            int horizon,
            String playbook,
            String repairInstruction
    ) {
        StringBuilder builder = new StringBuilder();
        builder.append("You are MarketBrain's local Ollama swing-ranking research assistant.\n\n");
        builder.append("Instruction pack version: ").append(INSTRUCTION_PACK_VERSION).append('\n');
        builder.append("Rubric version: ").append(RUBRIC_VERSION).append('\n');
        builder.append("Response schema version: ").append(RESPONSE_SCHEMA_VERSION).append("\n\n");
        builder.append(playbook).append('\n');
        builder.append("Dataset run: ").append(audit.datasetRunId()).append('\n');
        builder.append("As of: ").append(audit.asOf()).append('\n');
        builder.append("Requested horizon sessions: ").append(horizon).append("\n\n");
        builder.append("""
                Ranking objective for this request:
                - Select the best swing candidates for the requested horizon, not the best-looking chart.
                - Reward likely net return, likely benchmark excess, and smoother path quality.
                - Penalize likely benchmark lag, high volatility/drawdown pain, weak participation, and overextension.
                - A top-ranked candidate should normally deserve at least a strong score; weak or conflicted candidates should not receive HIGH confidence.
                - First rank the candidates qualitatively. Then calibrate scores from that rank order: rank 1 should not be HIGH unless its risk flags are genuinely small.
                - If a candidate has negative daily return, weak volume, high volatility, bearish EMA, or price below short/medium averages, mention the conflict and cap confidence unless other evidence is overwhelming.
                - Use feature_prior_score and feature_prior_bucket as a starting prior. Do not top-rank a LOW prior unless its recovery_tag is RECOVERY_CANDIDATE and peers have stronger overextension/risk traps.
                - Use feature_prior_rank as the baseline order. Moving away from it requires explicit evidence in the reason field.
                - Use the supplied MarketBrain algorithm exactly. Java has already calculated the raw signed contributions and feature prior. Your job is to review/rank inside this contract, not invent another scoring method.
                - You are not the executor. You are a reviewer/challenger. Java will arbitrate your rank against the deterministic baseline after your response.

                """);
        builder.append("""
                MarketBrain deterministic ranking algorithm contract:
                1. Treat feature_prior_rank as the baseline rank for this chunk.
                2. Treat feature_prior_score as Java's bounded 0..100 baseline score.
                3. The input contribution fields are signed/positive Java factors except penalty columns:
                   - trend_score can be negative or positive.
                   - momentum_score can be negative or positive.
                   - participation_score can be negative or positive.
                   - risk_penalty is a positive penalty in the input; report it as a negative signed contribution in JSON.
                   - recovery_credit is a positive contribution in the input.
                   - overextension_penalty is a positive penalty in the input; report it as a negative signed contribution in JSON.
                4. finalScore must equal your top-level score within 10 points and stay inside 0..100.
                5. If rank differs from feature_prior_rank by more than one position, the reason must name the exact feature conflict or recovery/overextension evidence.
                6. Score cap hints are mandatory guardrails unless the reason explains exceptional cross-feature evidence.

                Exact response DTO to populate:
                RankingResponseDto {
                  string schemaVersion = "MARKETBRAIN_OLLAMA_RANKING_RESPONSE_V3";
                  integer rankingHorizonSessions;
                  RankedCandidateDto[] rankedCandidates;
                  string riskNote;
                  string researchOnlyDisclaimer;
                }
                RankedCandidateDto {
                  integer rank;                 // complete sequence 1..candidateCount
                  string candidateId;            // exact supplied candidateId
                  string symbol;                 // exact supplied symbol for candidateId
                  integer score;                 // 0..100
                  string confidence;             // LOW | MEDIUM | HIGH
                  string[] positiveEvidence;     // feature-specific positives only
                  string[] riskFlags;            // feature-specific risks, or []
                  SignedContributionsDto signedContributions;
                  string reason;                 // concise feature-based explanation
                  boolean notTradingSignal = true;
                }
                SignedContributionsDto {
                  integer trendContribution;        // -100..100
                  integer momentumContribution;     // -100..100
                  integer participationContribution;// -100..100
                  integer riskPenalty;              // -100..100, normally zero or negative
                  integer recoveryCredit;            // -100..100, normally zero or positive
                  integer overextensionPenalty;      // -100..100, normally zero or negative
                  integer algorithmAdjustment;       // -100..100, only for relative/tie-break adjustment
                  integer finalScore;                // 0..100, within 10 points of score
                }

                """);
        builder.append("Labelled training examples. Learn patterns from these examples; do not rank these symbols:\n");
        builder.append("scenario,symbol,daily_return_pct,sma20,sma50,sma200,rsi14,atr14,volatility20_pct,volume_ratio20,range_position252_pct,target_net_return_pct,target_benchmark_excess_pct,target_max_drawdown_pct,teaching_point\n");
        for (PrototypeSwingOllamaTrainingExample example : examples) {
            builder.append(example.scenarioType()).append(',')
                    .append(example.symbol()).append(',')
                    .append(text(example.dailyReturnPercent())).append(',')
                    .append(text(example.sma20())).append(',')
                    .append(text(example.sma50())).append(',')
                    .append(text(example.sma200())).append(',')
                    .append(text(example.rsi14())).append(',')
                    .append(text(example.atr14())).append(',')
                    .append(text(example.annualizedVolatility20Percent())).append(',')
                    .append(text(example.volumeRatio20())).append(',')
                    .append(text(example.rangePosition252Percent())).append(',')
                    .append(text(example.targetNetReturnPercent())).append(',')
                    .append(text(example.targetBenchmarkExcessReturnPercent())).append(',')
                    .append(text(example.targetMaximumDrawdownPercent())).append(',')
                    .append('"').append(example.teachingPoint()).append('"').append('\n');
        }
        builder.append("\nUnlabelled ranking candidates. Use only these feature values and derived guardrail tags for ranking; future labels are hidden:\n");
        Map<String, Integer> priorRanks = featurePriorRanks(candidates);
        builder.append("candidate_id,symbol,close,daily_return_pct,sma20,sma50,sma200,ema12,ema26,rsi14,atr14,volatility20_pct,volume_ratio20,range_position252_pct,trend_tag,ema_tag,rsi_tag,volume_tag,volatility_tag,range_tag,recovery_tag,overextension_tag,trend_score,momentum_score,participation_score,risk_penalty,recovery_credit,overextension_penalty,feature_prior_score,feature_prior_rank,feature_prior_bucket,score_cap_hint\n");
        for (int index = 0; index < candidates.size(); index++) {
            PrototypeSwingOllamaCandidate candidate = candidates.get(index);
            int featurePriorScore = featurePriorScore(candidate);
            builder.append(candidateId(index)).append(',')
                    .append(candidate.symbol()).append(',')
                    .append(text(candidate.latestClose())).append(',')
                    .append(text(candidate.dailyReturnPercent())).append(',')
                    .append(text(candidate.sma20())).append(',')
                    .append(text(candidate.sma50())).append(',')
                    .append(text(candidate.sma200())).append(',')
                    .append(text(candidate.ema12())).append(',')
                    .append(text(candidate.ema26())).append(',')
                    .append(text(candidate.rsi14())).append(',')
                    .append(text(candidate.atr14())).append(',')
                    .append(text(candidate.annualizedVolatility20Percent())).append(',')
                    .append(text(candidate.volumeRatio20())).append(',')
                    .append(text(candidate.rangePosition252Percent())).append(',')
                    .append(trendTag(candidate)).append(',')
                    .append(emaTag(candidate)).append(',')
                    .append(rsiTag(candidate)).append(',')
                    .append(volumeTag(candidate)).append(',')
                    .append(volatilityTag(candidate)).append(',')
                    .append(rangeTag(candidate)).append(',')
                    .append(recoveryTag(candidate)).append(',')
                    .append(overextensionTag(candidate)).append(',')
                    .append(trendScore(candidate)).append(',')
                    .append(momentumScore(candidate)).append(',')
                    .append(participationScore(candidate)).append(',')
                    .append(riskPenalty(candidate)).append(',')
                    .append(recoveryCredit(candidate)).append(',')
                    .append(overextensionPenalty(candidate)).append(',')
                    .append(featurePriorScore).append(',')
                    .append(priorRanks.get(candidate.symbol())).append(',')
                    .append(featurePriorBucket(featurePriorScore)).append(',')
                    .append(scoreCapHint(candidate)).append('\n');
        }
        builder.append("\nExact rankedCandidates skeleton for this request. Return these candidateId/symbol pairs exactly once each; only decide rank, score, confidence and reasoning:\n");
        builder.append("[\n");
        for (int index = 0; index < candidates.size(); index++) {
            PrototypeSwingOllamaCandidate candidate = candidates.get(index);
            builder.append("  {\"candidateId\":\"")
                    .append(candidateId(index))
                    .append("\",\"symbol\":\"")
                    .append(candidate.symbol())
                    .append("\"}");
            if (index < candidates.size() - 1) {
                builder.append(',');
            }
            builder.append('\n');
        }
        builder.append("]\n");
        if (!repairInstruction.isBlank()) {
            builder.append("\nRepair instruction from the previous guarded attempt:\n");
            builder.append(repairInstruction).append("\n");
        }
        builder.append("""

                Return ONLY valid JSON, no markdown and no prose outside JSON.
                Required JSON shape:
                {
                  "schemaVersion": "MARKETBRAIN_OLLAMA_RANKING_RESPONSE_V3",
                  "rankingHorizonSessions": 20,
                  "rankedCandidates": [
                    {
                      "rank": 1,
                      "candidateId": "CANDIDATE_001",
                      "symbol": "SYMBOL",
                      "score": 0,
                      "confidence": "LOW",
                      "positiveEvidence": ["specific feature-based reason"],
                      "riskFlags": ["specific risk or empty array"],
                      "signedContributions": {
                        "trendContribution": 0,
                        "momentumContribution": 0,
                        "participationContribution": 0,
                        "riskPenalty": 0,
                        "recoveryCredit": 0,
                        "overextensionPenalty": 0,
                        "algorithmAdjustment": 0,
                        "finalScore": 0
                      },
                      "reason": "one concise feature-based explanation",
                      "notTradingSignal": true
                    }
                  ],
                  "riskNote": "portfolio-level risk note including survivorship risk",
                  "researchOnlyDisclaimer": "Prototype research only; creates no signal/order."
                }
                Rules: include every supplied candidateId exactly once; ranks must be 1..candidateCount;
                copy the symbol exactly from the row matching that candidateId;
                score must be 0..100; confidence must be LOW, MEDIUM, or HIGH; notTradingSignal must be true.
                Score calibration rubric:
                - 85..100: exceptional multi-factor setup with strong trend, participation, likely benchmark excess, controlled volatility/drawdown and almost no conflicts. HIGH confidence is allowed only here.
                - 70..84: strong setup with mostly aligned evidence, manageable risk and no major benchmark-lag or drawdown-like warning.
                - 55..69: constructive watchlist candidate, but with unresolved conflicts, weak participation, or merely average risk/reward.
                - 40..54: mixed evidence, meaningful risk, weak participation, overextension, or likely benchmark lag; usually lower rank.
                - 20..39: weak, risky, poor participation, high pain/drawdown profile, or expected laggard.
                - 0..19: avoid/very weak within this candidate batch.
                Use the full 0..100 range when candidates differ materially. Do not compress all scores near zero.
                Confidence calibration:
                - HIGH: only when evidence is broad, conflicts are minimal and the score is at least 85.
                - MEDIUM: use for strong but imperfect candidates.
                - LOW: use for candidates with negative daily return, weak participation, high volatility, overextension, or conflicting signals.
                Never assign HIGH confidence to a candidate whose reason contains major caveats such as weak RSI, weak volume, high volatility, overbought/overextended, or meaningful drawdown risk.
                Apply score_cap_hint unless you have exceptional cross-feature evidence:
                - HARD_CAP_54 means score must normally be 54 or lower and confidence must be LOW unless the candidate is clearly the least-bad option.
                - HARD_CAP_69 means score must normally be 69 or lower and confidence must not be HIGH.
                - SOFT_CAP_84 means score must normally be 84 or lower and confidence should be MEDIUM at most.
                - HIGH_ELIGIBLE means the candidate may receive 85+ only if it is also the best relative setup in this chunk.
                Feature prior usage:
                - Start from feature_prior_score/bucket, then adjust based on relative evidence.
                - Recovery candidates can outrank overextended traps even with lower RSI/range if volatility is controlled and participation is acceptable.
                - EXTREME_OVEREXTENSION candidates require explicit demotion unless every peer is worse.
                Signed contribution rules:
                - signedContributions values must be integers.
                - trendContribution, momentumContribution, participationContribution, riskPenalty, recoveryCredit, overextensionPenalty and algorithmAdjustment must be in -100..100.
                - Convert input penalties to negative signed contributions in JSON: riskPenalty and overextensionPenalty should normally be zero or negative.
                - finalScore must be consistent with score. A difference above 10 points is not allowed.
                - Mention recoveryCredit in reason if you top-rank a recovery candidate.
                - Mention overextensionPenalty in reason if you rank an extended candidate in the top two.
                """);
        return builder.toString();
    }

    String trendTag(PrototypeSwingOllamaCandidate candidate) {
        if (greater(candidate.latestClose(), candidate.sma20())
                && greaterOrEqual(candidate.sma20(), candidate.sma50())
                && greaterOrEqual(candidate.sma50(), candidate.sma200())) {
            return "BULLISH_TREND";
        }
        if (less(candidate.latestClose(), candidate.sma20()) || less(candidate.sma20(), candidate.sma50())) {
            return "TREND_CONFLICT";
        }
        return "MIXED_TREND";
    }

    String emaTag(PrototypeSwingOllamaCandidate candidate) {
        return greaterOrEqual(candidate.ema12(), candidate.ema26()) ? "EMA_BULLISH" : "EMA_BEARISH";
    }

    String rsiTag(PrototypeSwingOllamaCandidate candidate) {
        if (candidate.rsi14() == null) {
            return "RSI_UNKNOWN";
        }
        if (candidate.rsi14().compareTo(BigDecimal.valueOf(70)) > 0) {
            return "RSI_OVERHEATED";
        }
        if (candidate.rsi14().compareTo(BigDecimal.valueOf(55)) >= 0) {
            return "RSI_CONSTRUCTIVE";
        }
        if (candidate.rsi14().compareTo(BigDecimal.valueOf(45)) < 0) {
            return "RSI_WEAK";
        }
        return "RSI_NEUTRAL";
    }

    String volumeTag(PrototypeSwingOllamaCandidate candidate) {
        if (candidate.volumeRatio20() == null) {
            return "VOLUME_UNKNOWN";
        }
        if (candidate.volumeRatio20().compareTo(BigDecimal.valueOf(1.2)) >= 0) {
            return "VOLUME_CONFIRMED";
        }
        if (candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.8)) < 0) {
            return "VOLUME_WEAK";
        }
        return "VOLUME_NEUTRAL";
    }

    String volatilityTag(PrototypeSwingOllamaCandidate candidate) {
        if (candidate.annualizedVolatility20Percent() == null) {
            return "VOLATILITY_UNKNOWN";
        }
        if (candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(35)) > 0) {
            return "VOLATILITY_HIGH";
        }
        if (candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(20)) < 0) {
            return "VOLATILITY_CONTROLLED";
        }
        return "VOLATILITY_MODERATE";
    }

    String rangeTag(PrototypeSwingOllamaCandidate candidate) {
        if (candidate.rangePosition252Percent() == null) {
            return "RANGE_UNKNOWN";
        }
        if (candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(90)) > 0) {
            return "RANGE_EXTENDED";
        }
        if (candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(60)) >= 0) {
            return "RANGE_LEADERSHIP";
        }
        if (candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(30)) < 0) {
            return "RANGE_LOW";
        }
        return "RANGE_MIDDLE";
    }

    String scoreCapHint(PrototypeSwingOllamaCandidate candidate) {
        int majorConflicts = 0;
        if (less(candidate.latestClose(), candidate.sma20())) {
            majorConflicts++;
        }
        if (less(candidate.sma20(), candidate.sma50())) {
            majorConflicts++;
        }
        if (less(candidate.ema12(), candidate.ema26())) {
            majorConflicts++;
        }
        if (candidate.rsi14() != null && candidate.rsi14().compareTo(BigDecimal.valueOf(45)) < 0) {
            majorConflicts++;
        }
        if (candidate.volumeRatio20() != null && candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.8)) < 0) {
            majorConflicts++;
        }
        if (candidate.annualizedVolatility20Percent() != null
                && candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(35)) > 0) {
            majorConflicts++;
        }
        if (candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(90)) > 0
                && candidate.rsi14() != null
                && candidate.rsi14().compareTo(BigDecimal.valueOf(65)) > 0) {
            majorConflicts++;
        }
        if (candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(95)) > 0
                && candidate.volumeRatio20() != null
                && candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.8)) < 0) {
            majorConflicts++;
        }
        if (isExtremeRisk(candidate)) {
            return "HARD_CAP_54";
        }
        if (majorConflicts >= 2) {
            return "HARD_CAP_69";
        }
        if (majorConflicts == 1) {
            return "SOFT_CAP_84";
        }
        return "HIGH_ELIGIBLE";
    }

    String recoveryTag(PrototypeSwingOllamaCandidate candidate) {
        if (candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(40)) < 0
                && candidate.annualizedVolatility20Percent() != null
                && candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(30)) <= 0
                && candidate.volumeRatio20() != null
                && candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.7)) >= 0) {
            return "RECOVERY_CANDIDATE";
        }
        return "NOT_RECOVERY";
    }

    String overextensionTag(PrototypeSwingOllamaCandidate candidate) {
        if (isExtremeRisk(candidate)) {
            return "EXTREME_OVEREXTENSION";
        }
        if (candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(90)) > 0) {
            return "EXTENDED";
        }
        return "NOT_EXTENDED";
    }

    int featurePriorScore(PrototypeSwingOllamaCandidate candidate) {
        int score = 40
                + trendScore(candidate)
                + momentumScore(candidate)
                + participationScore(candidate)
                + recoveryCredit(candidate)
                - riskPenalty(candidate)
                - overextensionPenalty(candidate);
        return clamp(score);
    }

    Map<String, Integer> featurePriorRanks(List<PrototypeSwingOllamaCandidate> candidates) {
        List<PrototypeSwingOllamaCandidate> sorted = new ArrayList<>(candidates);
        sorted.sort(java.util.Comparator
                .comparingInt((PrototypeSwingOllamaCandidate candidate) -> featurePriorScore(candidate))
                .reversed()
                .thenComparing(PrototypeSwingOllamaCandidate::symbol));
        Map<String, Integer> ranks = new HashMap<>();
        for (int index = 0; index < sorted.size(); index++) {
            ranks.put(sorted.get(index).symbol(), index + 1);
        }
        return ranks;
    }

    int trendScore(PrototypeSwingOllamaCandidate candidate) {
        int score = 0;
        if ("BULLISH_TREND".equals(trendTag(candidate))) {
            score += 16;
        } else if ("MIXED_TREND".equals(trendTag(candidate))) {
            score += 6;
        } else {
            score -= 8;
        }
        score += distanceScore(candidate.latestClose(), candidate.sma20(), 6, -6);
        score += distanceScore(candidate.latestClose(), candidate.sma50(), 5, -5);
        return score;
    }

    int momentumScore(PrototypeSwingOllamaCandidate candidate) {
        int score = "EMA_BULLISH".equals(emaTag(candidate)) ? 8 : -8;
        score += switch (rsiTag(candidate)) {
            case "RSI_CONSTRUCTIVE" -> 12;
            case "RSI_NEUTRAL" -> 5;
            case "RSI_WEAK" -> "RECOVERY_CANDIDATE".equals(recoveryTag(candidate)) ? 2 : -8;
            case "RSI_OVERHEATED" -> -10;
            default -> 0;
        };
        if (candidate.dailyReturnPercent() != null) {
            if (candidate.dailyReturnPercent().compareTo(BigDecimal.valueOf(0)) < 0
                    && "RECOVERY_CANDIDATE".equals(recoveryTag(candidate))) {
                score += 4;
            } else if (candidate.dailyReturnPercent().compareTo(BigDecimal.valueOf(3)) > 0) {
                score -= "EXTREME_OVEREXTENSION".equals(overextensionTag(candidate)) ? 12 : 2;
            }
        }
        return score;
    }

    int participationScore(PrototypeSwingOllamaCandidate candidate) {
        return switch (volumeTag(candidate)) {
            case "VOLUME_CONFIRMED" -> 12;
            case "VOLUME_NEUTRAL" -> 5;
            case "VOLUME_WEAK" -> "RECOVERY_CANDIDATE".equals(recoveryTag(candidate)) ? -2 : -10;
            default -> 0;
        };
    }

    int riskPenalty(PrototypeSwingOllamaCandidate candidate) {
        int penalty = switch (volatilityTag(candidate)) {
            case "VOLATILITY_HIGH" -> 18;
            case "VOLATILITY_MODERATE" -> 5;
            default -> 0;
        };
        if (candidate.annualizedVolatility20Percent() != null
                && candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(45)) > 0) {
            penalty += 8;
        }
        if (candidate.atr14() != null && candidate.latestClose() != null
                && candidate.latestClose().compareTo(BigDecimal.ZERO) > 0
                && candidate.atr14().multiply(BigDecimal.valueOf(100))
                .divide(candidate.latestClose(), 6, java.math.RoundingMode.HALF_UP)
                .compareTo(BigDecimal.valueOf(4)) > 0) {
            penalty += 6;
        }
        return penalty;
    }

    int recoveryCredit(PrototypeSwingOllamaCandidate candidate) {
        if (!"RECOVERY_CANDIDATE".equals(recoveryTag(candidate))) {
            return 0;
        }
        int credit = 16;
        if ("VOLUME_NEUTRAL".equals(volumeTag(candidate)) || "VOLUME_CONFIRMED".equals(volumeTag(candidate))) {
            credit += 6;
        }
        if ("VOLATILITY_CONTROLLED".equals(volatilityTag(candidate)) || "VOLATILITY_MODERATE".equals(volatilityTag(candidate))) {
            credit += 6;
        }
        return credit;
    }

    int overextensionPenalty(PrototypeSwingOllamaCandidate candidate) {
        int penalty = 0;
        if ("EXTREME_OVEREXTENSION".equals(overextensionTag(candidate))) {
            penalty += 24;
        } else if ("EXTENDED".equals(overextensionTag(candidate))) {
            penalty += 8;
        }
        if (candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(98)) > 0
                && candidate.volumeRatio20() != null
                && candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.8)) < 0) {
            penalty += 12;
        }
        return penalty;
    }

    String featurePriorBucket(int score) {
        if (score >= 75) {
            return "HIGH_PRIOR";
        }
        if (score >= 60) {
            return "MEDIUM_PRIOR";
        }
        if (score >= 45) {
            return "LOW_PRIOR";
        }
        return "AVOID_PRIOR";
    }

    private boolean isExtremeRisk(PrototypeSwingOllamaCandidate candidate) {
        boolean highVolatility = candidate.annualizedVolatility20Percent() != null
                && candidate.annualizedVolatility20Percent().compareTo(BigDecimal.valueOf(35)) > 0;
        boolean weakVolume = candidate.volumeRatio20() != null
                && candidate.volumeRatio20().compareTo(BigDecimal.valueOf(0.8)) < 0;
        boolean hotExtended = candidate.rangePosition252Percent() != null
                && candidate.rangePosition252Percent().compareTo(BigDecimal.valueOf(90)) > 0
                && candidate.rsi14() != null
                && candidate.rsi14().compareTo(BigDecimal.valueOf(65)) > 0;
        boolean dailySpike = candidate.dailyReturnPercent() != null
                && candidate.dailyReturnPercent().compareTo(BigDecimal.valueOf(3)) > 0;
        return (highVolatility && weakVolume)
                || (highVolatility && hotExtended)
                || (dailySpike && highVolatility && hotExtended);
    }

    String featurePriorReason(PrototypeSwingOllamaCandidate candidate) {
        return "Java baseline: trend=%s(%d), momentum=%s(%d), participation=%s(%d), riskPenalty=%d, recovery=%s(%d), overextension=%s(%d), cap=%s"
                .formatted(
                        trendTag(candidate), trendScore(candidate),
                        rsiTag(candidate) + "/" + emaTag(candidate), momentumScore(candidate),
                        volumeTag(candidate), participationScore(candidate),
                        riskPenalty(candidate),
                        recoveryTag(candidate), recoveryCredit(candidate),
                        overextensionTag(candidate), overextensionPenalty(candidate),
                        scoreCapHint(candidate)
                );
    }

    private int distanceScore(BigDecimal price, BigDecimal average, int positive, int negative) {
        if (price == null || average == null || average.compareTo(BigDecimal.ZERO) == 0) {
            return 0;
        }
        BigDecimal distancePercent = price.subtract(average)
                .multiply(BigDecimal.valueOf(100))
                .divide(average, 6, java.math.RoundingMode.HALF_UP);
        if (distancePercent.compareTo(BigDecimal.valueOf(10)) > 0) {
            return Math.max(0, positive - 4);
        }
        if (distancePercent.compareTo(BigDecimal.ZERO) >= 0) {
            return positive;
        }
        if (distancePercent.compareTo(BigDecimal.valueOf(-5)) >= 0) {
            return negative / 2;
        }
        return negative;
    }

    private int clamp(int value) {
        return Math.max(0, Math.min(100, value));
    }

    private boolean greater(BigDecimal left, BigDecimal right) {
        return left != null && right != null && left.compareTo(right) > 0;
    }

    private boolean greaterOrEqual(BigDecimal left, BigDecimal right) {
        return left != null && right != null && left.compareTo(right) >= 0;
    }

    private boolean less(BigDecimal left, BigDecimal right) {
        return left != null && right != null && left.compareTo(right) < 0;
    }

    private Validation validateResponse(
            String response,
            List<PrototypeSwingOllamaCandidate> candidates,
            int horizon
    ) {
        List<String> failures = new ArrayList<>();
        JsonNode root;
        try {
            root = objectMapper.readTree(response);
        } catch (Exception exception) {
            return new Validation(false, List.of("RESPONSE_NOT_PARSEABLE_JSON"));
        }
        if (!RESPONSE_SCHEMA_VERSION.equals(root.path("schemaVersion").asText())) {
            failures.add("SCHEMA_VERSION");
        }
        if (root.path("rankingHorizonSessions").asInt(-1) != horizon) {
            failures.add("RANKING_HORIZON");
        }
        JsonNode ranked = root.path("rankedCandidates");
        if (!ranked.isArray() || ranked.size() != candidates.size()) {
            failures.add("RANKED_CANDIDATE_COUNT");
        }
        Map<String, String> expectedSymbolByCandidateId = new HashMap<>();
        Set<String> expectedCandidateIds = new HashSet<>();
        Set<String> expectedSymbols = new HashSet<>();
        for (int index = 0; index < candidates.size(); index++) {
            String candidateId = candidateId(index);
            String symbol = candidates.get(index).symbol();
            expectedCandidateIds.add(candidateId);
            expectedSymbols.add(symbol);
            expectedSymbolByCandidateId.put(candidateId, symbol);
        }
        Set<String> seenCandidateIds = new HashSet<>();
        Set<String> seenSymbols = new HashSet<>();
        Set<Integer> seenRanks = new HashSet<>();
        for (JsonNode node : ranked) {
            String candidateId = node.path("candidateId").asText("");
            String symbol = node.path("symbol").asText("");
            int rank = node.path("rank").asInt(-1);
            int score = node.path("score").asInt(-1);
            String confidence = node.path("confidence").asText("");
            if (!expectedCandidateIds.contains(candidateId) || !seenCandidateIds.add(candidateId)) {
                failures.add("CANDIDATE_ID_SET");
            } else if (!expectedSymbolByCandidateId.get(candidateId).equals(symbol)) {
                failures.add("CANDIDATE_SYMBOL_MISMATCH");
            }
            if (!expectedSymbols.contains(symbol) || !seenSymbols.add(symbol)) {
                failures.add("SYMBOL_SET");
            }
            if (rank < 1 || rank > candidates.size() || !seenRanks.add(rank)) {
                failures.add("RANK_SEQUENCE");
            }
            if (score < 0 || score > 100) {
                failures.add("SCORE_RANGE");
            }
            if (!List.of("LOW", "MEDIUM", "HIGH").contains(confidence)) {
                failures.add("CONFIDENCE_VALUE");
            }
            if (!node.path("notTradingSignal").asBoolean(false)) {
                failures.add("NOT_TRADING_SIGNAL_FLAG");
            }
            if (!node.path("positiveEvidence").isArray()
                    || !node.path("riskFlags").isArray()
                    || node.path("reason").asText("").isBlank()) {
                failures.add("REASONING_FIELDS");
            }
            JsonNode signedContributions = node.path("signedContributions");
            if (!signedContributions.isObject()) {
                failures.add("SIGNED_CONTRIBUTIONS_OBJECT");
            } else {
                validateSignedContribution(signedContributions, "trendContribution", failures);
                validateSignedContribution(signedContributions, "momentumContribution", failures);
                validateSignedContribution(signedContributions, "participationContribution", failures);
                validateSignedContribution(signedContributions, "riskPenalty", failures);
                validateSignedContribution(signedContributions, "recoveryCredit", failures);
                validateSignedContribution(signedContributions, "overextensionPenalty", failures);
                validateSignedContribution(signedContributions, "algorithmAdjustment", failures);
                int finalScore = validateFinalScore(signedContributions, failures);
                if (finalScore >= 0 && Math.abs(finalScore - score) > 10) {
                    failures.add("SIGNED_CONTRIBUTION_FINAL_SCORE_MISMATCH:" + symbol
                            + ":score=" + score + ":finalScore=" + finalScore);
                }
            }
        }
        if (root.path("riskNote").asText("").isBlank()
                || root.path("researchOnlyDisclaimer").asText("").isBlank()) {
            failures.add("REQUIRED_NOTES");
        }
        return new Validation(true, failures.stream().distinct().toList());
    }

    private int validateSignedContribution(JsonNode signedContributions, String field, List<String> failures) {
        if (!signedContributions.has(field) || !signedContributions.path(field).canConvertToInt()) {
            failures.add("SIGNED_CONTRIBUTION_MISSING:" + field);
            return -1;
        }
        int value = signedContributions.path(field).asInt(-999);
        if (value < -100 || value > 100) {
            failures.add("SIGNED_CONTRIBUTION_RANGE:" + field + "=" + value + ":expected=-100..100");
        }
        return value;
    }

    private int validateFinalScore(JsonNode signedContributions, List<String> failures) {
        if (!signedContributions.has("finalScore") || !signedContributions.path("finalScore").canConvertToInt()) {
            failures.add("SIGNED_CONTRIBUTION_MISSING:finalScore");
            return -1;
        }
        int value = signedContributions.path("finalScore").asInt(-1);
        if (value < 0 || value > 100) {
            failures.add("SIGNED_CONTRIBUTION_FINAL_SCORE_RANGE:finalScore=" + value + ":expected=0..100");
        }
        return value;
    }

    static String candidateId(int zeroBasedIndex) {
        return "CANDIDATE_%03d".formatted(zeroBasedIndex + 1);
    }

    private String repairInstruction(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        String trimmed = value.trim();
        if (trimmed.length() > 2000) {
            trimmed = trimmed.substring(0, 2000);
        }
        return trimmed.replace('\r', ' ').replace('\n', ' ');
    }

    private String model(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("model is required.");
        }
        String trimmed = value.trim();
        if (trimmed.length() > 80 || !trimmed.matches("^[A-Za-z0-9._:/-]+$")) {
            throw new IllegalArgumentException("model contains unsupported characters.");
        }
        return trimmed;
    }

    private int candidateLimit(Integer value) {
        int limit = value == null ? DEFAULT_CANDIDATE_LIMIT : value;
        if (limit < 1 || limit > MAXIMUM_CANDIDATE_LIMIT) {
            throw new IllegalArgumentException("candidateLimit must be between 1 and 25.");
        }
        return limit;
    }

    private int horizon(Integer value) {
        int horizon = value == null ? DEFAULT_RANKING_HORIZON_SESSIONS : value;
        if (!SwingTrainingDatasetPreviewService.HORIZONS.contains(horizon)) {
            throw new IllegalArgumentException("rankingHorizonSessions must be one of 5, 20, or 60.");
        }
        return horizon;
    }

    private String text(BigDecimal value) {
        if (value == null) {
            return "";
        }
        return value.stripTrailingZeros().toPlainString();
    }

    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)))
                    .toLowerCase(Locale.ROOT);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable.", exception);
        }
    }

    private record Validation(boolean parseableJson, List<String> failures) {
    }
}
