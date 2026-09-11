package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

@Service
public class PrototypeSwingOllamaRankingPreviewService {

    static final int DEFAULT_CANDIDATE_LIMIT = 12;
    static final int MAXIMUM_CANDIDATE_LIMIT = 25;
    static final int DEFAULT_RANKING_HORIZON_SESSIONS = 20;

    private final PrototypeSwingTrainingDatasetAuditService auditService;
    private final PrototypeSwingOllamaClient ollamaClient;
    private final JdbcTemplate jdbcTemplate;

    public PrototypeSwingOllamaRankingPreviewService(
            PrototypeSwingTrainingDatasetAuditService auditService,
            PrototypeSwingOllamaClient ollamaClient,
            JdbcTemplate jdbcTemplate
    ) {
        this.auditService = auditService;
        this.ollamaClient = ollamaClient;
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional(readOnly = true, timeout = 600)
    public PrototypeSwingOllamaRankingPreview preview(PrototypeSwingOllamaRankingRequest request) {
        PrototypeSwingOllamaRankingRequest safeRequest = request == null
                ? new PrototypeSwingOllamaRankingRequest(null, null, null, null)
                : request;
        String model = model(safeRequest.model());
        int candidateLimit = candidateLimit(safeRequest.candidateLimit());
        int horizon = horizon(safeRequest.rankingHorizonSessions());

        PrototypeSwingTrainingDatasetAudit audit = auditService.audit(safeRequest.datasetRunId());
        validateAudit(audit);
        List<PrototypeSwingOllamaCandidate> candidates = candidates(audit.datasetRunId(), candidateLimit);
        if (candidates.isEmpty()) {
            throw new IllegalStateException("No labelled prototype candidates are available for Ollama ranking.");
        }

        String prompt = prompt(audit, candidates, horizon);
        String response = ollamaClient.generate(model, prompt);
        return new PrototypeSwingOllamaRankingPreview(
                "REVIEW_REQUIRED",
                audit.datasetRunId(),
                audit.datasetContractVersion(),
                audit.sourceUniverseCode(),
                audit.asOf(),
                audit.labelThrough(),
                audit.datasetManifestHash(),
                model,
                candidateLimit,
                candidates.size(),
                horizon,
                sha256(prompt),
                sha256(response),
                prompt,
                response,
                candidates,
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
                "Ollama produced a prototype ranking explanation for review only. "
                        + "No signal, paper fill, order, or broker action was created."
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
            throw new IllegalStateException("The prototype dataset audit is not ready for Ollama ranking.");
        }
    }

    private List<PrototypeSwingOllamaCandidate> candidates(UUID runId, int limit) {
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
                        resultSet.getBigDecimal("maximum_drawdown_60")), runId, limit);
    }

    private String prompt(
            PrototypeSwingTrainingDatasetAudit audit,
            List<PrototypeSwingOllamaCandidate> candidates,
            int horizon
    ) {
        StringBuilder builder = new StringBuilder();
        builder.append("""
                You are MarketBrain's local Ollama reviewer for a prototype Indian equity swing-ranking experiment.

                Safety and scope:
                - This is NOT a live recommendation.
                - Do not instruct the user to buy, sell, hold, place an order, or contact a broker.
                - Rank only the supplied historical feature rows for research review.
                - The data uses current-snapshot NIFTY 500 membership, so survivorship risk is present.
                - Future labels are intentionally withheld from the prompt. Use only the feature columns below.

                Required output:
                1. A ranked list of the supplied symbols for the requested swing horizon.
                2. One short reason per symbol using only the supplied features.
                3. A short risk note covering volatility, drawdown risk, and survivorship risk.
                4. A final sentence that this is prototype research only and creates no signal/order.

                """);
        builder.append("Dataset run: ").append(audit.datasetRunId()).append('\n');
        builder.append("As of: ").append(audit.asOf()).append('\n');
        builder.append("Label-through date, hidden from ranking: ").append(audit.labelThrough()).append('\n');
        builder.append("Requested horizon sessions: ").append(horizon).append("\n\n");
        builder.append("Feature rows:\n");
        builder.append("symbol,close,daily_return_pct,sma20,sma50,sma200,ema12,ema26,rsi14,atr14,volatility20_pct,volume_ratio20,range_position252_pct\n");
        for (PrototypeSwingOllamaCandidate candidate : candidates) {
            builder.append(candidate.symbol()).append(',')
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
                    .append(text(candidate.rangePosition252Percent())).append('\n');
        }
        return builder.toString();
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
}
