package in.marketbrain.marketdata.backfill;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@Service
public class RemainingDataRemediationService {

    private static final String SECONDARY_SOURCE_CODE = "NSE_BHAVCOPY";
    private static final String UPSTOX_HISTORICAL_DOCUMENTATION_URL =
            "https://upstox.com/developer/api-documentation/v3/get-historical-candle-data/";
    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");
    private static final List<QualityResolutionType> SUPPORTED_RESOLUTIONS = List.of(
            QualityResolutionType.SECONDARY_SOURCE_BACKFILLED,
            QualityResolutionType.FEATURE_WINDOW_EXCLUDED,
            QualityResolutionType.PROVIDER_ADJUSTMENT,
            QualityResolutionType.VERIFIED_EXCHANGE_MOVE);

    private final RemainingDataAnalysisService analysisService;
    private final HistoricalBackfillJobService jobService;
    private final BackfillQualityService qualityService;
    private final QualityResolutionService resolutionService;
    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;

    public RemainingDataRemediationService(
            RemainingDataAnalysisService analysisService,
            HistoricalBackfillJobService jobService,
            BackfillQualityService qualityService,
            QualityResolutionService resolutionService,
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate
    ) {
        this.analysisService = analysisService;
        this.jobService = jobService;
        this.qualityService = qualityService;
        this.resolutionService = resolutionService;
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
    }

    public synchronized RemainingDataRemediationReport apply(RemainingDataRemediationRequest request) {
        requireSafeJob(request.jobId());
        Plan plan = findPlan(request.jobId());
        if (plan == null) {
            RemainingDataAnalysisReport analysis = analysisService.analyze(request.jobId());
            validateReviewedAnalysis(analysis, request.expectedPlanHash());
            plan = transactionTemplate.execute(status -> createPlan(analysis, request.reviewedBy().trim()));
            if (plan == null) {
                throw new IllegalStateException("The reviewed remediation plan could not be persisted");
            }
        } else {
            requireMatchingPlan(plan, request);
        }

        UUID planId = plan.id();
        transactionTemplate.executeWithoutResult(status -> markPlanRunning(planId));
        for (Long itemId : pendingItemIds(planId)) {
            try {
                transactionTemplate.executeWithoutResult(status -> completeItem(planId, itemId));
            } catch (RuntimeException exception) {
                transactionTemplate.executeWithoutResult(status -> markItemFailed(itemId, exception));
            }
        }
        transactionTemplate.executeWithoutResult(status -> finishPlan(planId));
        return report(request.jobId(), request.expectedPlanHash());
    }

    public RemainingDataRemediationReport status(UUID jobId, String expectedPlanHash) {
        Plan plan = findPlan(jobId);
        if (plan == null) {
            throw new IllegalArgumentException("No Step 21 remediation plan exists for this backfill job");
        }
        if (!plan.planHash().equals(expectedPlanHash)) {
            throw new IllegalStateException("The requested plan hash does not match the persisted Step 21 plan");
        }
        return report(jobId, expectedPlanHash);
    }

    void validateReviewedAnalysis(RemainingDataAnalysisReport analysis, String expectedPlanHash) {
        if (!analysis.analysisComplete() || analysis.keepOpenCount() != 0 || analysis.sourceFailureCount() != 0) {
            throw new IllegalStateException("Step 20 is incomplete; no Step 21 plan was persisted");
        }
        if (!analysis.planHash().equals(expectedPlanHash)) {
            throw new IllegalStateException(
                    "Live Step 20 hash " + analysis.planHash() + " does not match the reviewed hash");
        }
        if (analysis.items().size() != analysis.unresolvedFindingCount()) {
            throw new IllegalStateException("Step 20 does not contain exactly one item per unresolved finding");
        }
        int candidateCount = analysis.secondaryBackfillCandidateCount()
                + analysis.featureExclusionCandidateCount()
                + analysis.providerAdjustmentCandidateCount()
                + analysis.verifiedMoveCandidateCount();
        if (candidateCount != analysis.unresolvedFindingCount()) {
            throw new IllegalStateException("Step 20 candidate totals do not equal its unresolved finding total");
        }
        for (RemainingDataAnalysisReport.Item item : analysis.items()) {
            if (item.symbol() == null || item.symbol().isBlank()) {
                throw new IllegalStateException("Step 20 contains a finding without an instrument symbol");
            }
            if (item.recommendedResolutionType() == null
                    || !SUPPORTED_RESOLUTIONS.contains(item.recommendedResolutionType())) {
                throw new IllegalStateException("Step 20 contains an unsupported recommendation");
            }
            if (item.recommendedResolutionType().requiresExclusion()
                    && (item.exclusionFrom() == null || item.exclusionTo() == null)) {
                throw new IllegalStateException("Step 20 contains an unbounded feature exclusion");
            }
            if (item.recommendedResolutionType() == QualityResolutionType.SECONDARY_SOURCE_BACKFILLED
                    && !validOfficialCandle(item)) {
                throw new IllegalStateException("Step 20 contains an invalid secondary-source candle");
            }
        }
    }

    boolean validOfficialCandle(RemainingDataAnalysisReport.Item item) {
        return item.officialOpen() != null && item.officialHigh() != null
                && item.officialLow() != null && item.officialClose() != null
                && item.officialOpen().signum() > 0 && item.officialHigh().signum() > 0
                && item.officialLow().signum() > 0 && item.officialClose().signum() > 0
                && item.officialLow().compareTo(item.officialOpen()) <= 0
                && item.officialLow().compareTo(item.officialClose()) <= 0
                && item.officialHigh().compareTo(item.officialOpen()) >= 0
                && item.officialHigh().compareTo(item.officialClose()) >= 0
                && (item.officialVolume() == null || item.officialVolume().signum() >= 0);
    }

    private void requireSafeJob(UUID jobId) {
        BackfillJobSummary job = jobService.summary(jobId);
        if (!"COMPLETED".equals(job.status()) || job.failedChunks() != 0) {
            throw new IllegalStateException("Step 21 requires a completed backfill with no failed chunks");
        }
        if (job.workerEnabled()) {
            throw new IllegalStateException("MARKETBRAIN_BACKFILL_WORKER_ENABLED must be false during Step 21");
        }
    }

    private void requireMatchingPlan(Plan plan, RemainingDataRemediationRequest request) {
        if (!plan.planHash().equals(request.expectedPlanHash())) {
            throw new IllegalStateException("A different Step 21 plan already exists for this backfill job");
        }
        if (!plan.reviewedBy().equals(request.reviewedBy().trim())) {
            throw new IllegalStateException("Resume Step 21 with the same reviewedBy value used initially");
        }
    }

    private Plan createPlan(RemainingDataAnalysisReport analysis, String reviewedBy) {
        UUID planId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO remaining_data_remediation_plan
                    (id, job_id, plan_hash, status, reviewed_by, item_count)
                VALUES (?, ?, ?, 'READY', ?, ?)
                """, planId, analysis.jobId(), analysis.planHash(), reviewedBy, analysis.items().size());

        Map<String, InstrumentScope> instruments = jobInstruments(analysis.jobId());
        for (RemainingDataAnalysisReport.Item item : analysis.items()) {
            InstrumentScope instrument = instruments.get(item.symbol().toUpperCase(Locale.ROOT));
            if (instrument == null) {
                throw new IllegalStateException("Plan symbol is not part of the backfill job: " + item.symbol());
            }
            String evidenceUrl = item.evidenceUrl();
            String evidenceSource = item.evidenceSource();
            if (evidenceUrl == null || evidenceUrl.isBlank()) {
                evidenceUrl = instrument.listingEvidenceUrl() == null
                        ? UPSTOX_HISTORICAL_DOCUMENTATION_URL : instrument.listingEvidenceUrl();
                evidenceSource = instrument.listingEvidenceUrl() == null
                        ? "Upstox V3 historical API documentation and MarketBrain persisted coverage audit"
                        : "NSE listing evidence and MarketBrain persisted coverage audit";
            }
            if (evidenceUrl == null || !evidenceUrl.startsWith("https://")) {
                throw new IllegalStateException("No HTTPS evidence URL exists for " + item.symbol());
            }
            jdbcTemplate.update("""
                    INSERT INTO remaining_data_remediation_item
                        (plan_id, instrument_id, symbol, finding_type, finding_date, related_date,
                         analysis_status, resolution_type, exclusion_from, exclusion_to,
                         official_symbol, match_basis, official_series,
                         official_open, official_high, official_low, official_close, official_volume,
                         evidence_source, evidence_url, detail)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, planId, instrument.id(), item.symbol(), item.findingType().name(),
                    Date.valueOf(item.findingDate()), dateOrNull(item.relatedDate()), item.analysisStatus(),
                    item.recommendedResolutionType().name(), dateOrNull(item.exclusionFrom()),
                    dateOrNull(item.exclusionTo()), item.officialSymbol(), item.matchBasis(), item.officialSeries(),
                    item.officialOpen(), item.officialHigh(), item.officialLow(), item.officialClose(),
                    item.officialVolume(), evidenceSource, evidenceUrl, limited(item.detail(), 1000));
        }
        Integer inserted = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM remaining_data_remediation_item WHERE plan_id = ?",
                Integer.class, planId);
        if (inserted == null || inserted != analysis.items().size()) {
            throw new IllegalStateException("The complete reviewed plan was not persisted atomically");
        }
        return findPlanById(planId);
    }

    private Map<String, InstrumentScope> jobInstruments(UUID jobId) {
        Map<String, InstrumentScope> result = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT chunk.source_symbol, instrument.id, instrument.listing_date_source_url
                FROM historical_backfill_chunk chunk
                JOIN instrument ON instrument.id = chunk.instrument_id
                WHERE chunk.job_id = ?
                """, (org.springframework.jdbc.core.RowCallbackHandler) rs -> result.put(
                rs.getString("source_symbol").toUpperCase(Locale.ROOT),
                new InstrumentScope(rs.getLong("id"), rs.getString("listing_date_source_url"))), jobId);
        return Map.copyOf(result);
    }

    private void markPlanRunning(UUID planId) {
        jdbcTemplate.update("""
                UPDATE remaining_data_remediation_plan
                SET status = 'RUNNING', started_at = COALESCE(started_at, CURRENT_TIMESTAMP),
                    completed_at = NULL, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status <> 'COMPLETED'
                """, planId);
    }

    private List<Long> pendingItemIds(UUID planId) {
        return jdbcTemplate.query("""
                SELECT id FROM remaining_data_remediation_item
                WHERE plan_id = ? AND status <> 'COMPLETED'
                ORDER BY id
                """, (rs, row) -> rs.getLong("id"), planId);
    }

    private void completeItem(UUID planId, long itemId) {
        PlanItem item = findPlanItemForUpdate(planId, itemId);
        if ("COMPLETED".equals(item.status())) {
            return;
        }
        boolean secondaryReady = false;
        if (item.resolutionType() == QualityResolutionType.SECONDARY_SOURCE_BACKFILLED) {
            ensureSecondaryCandle(item);
            secondaryReady = true;
        }
        Plan plan = findPlanById(planId);
        QualityResolutionRecord resolution = resolutionService.resolve(new QualityResolutionRequest(
                plan.jobId(), item.symbol(), item.findingType(), item.findingDate(), item.relatedDate(),
                item.resolutionType(), item.evidenceSource(), item.evidenceUrl(),
                limited("Step 21 plan " + plan.planHash() + ": " + item.analysisStatus()
                        + ". " + item.detail(), 1000),
                plan.reviewedBy(), item.exclusionFrom(), item.exclusionTo()));
        jdbcTemplate.update("""
                UPDATE remaining_data_remediation_item
                SET status = 'COMPLETED', attempts = attempts + 1,
                    secondary_candle_ready = ?, resolution_event_id = ?,
                    last_error_code = NULL, last_error_detail = NULL,
                    completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """, secondaryReady, resolution.id(), itemId);
    }

    private void ensureSecondaryCandle(PlanItem item) {
        if (!validOfficialCandle(item)) {
            throw new IllegalStateException("The persisted official candle failed validation");
        }
        Timestamp canonicalTimestamp = Timestamp.from(item.findingDate().atStartOfDay(INDIA).toInstant());
        jdbcTemplate.update("""
                INSERT INTO market_candle
                    (instrument_id, source_id, interval_code, opened_at, provider_opened_at,
                     source_published_at, open_price, high_price, low_price, close_price, volume, is_complete)
                SELECT ?, source.id, 'days:1', ?, ?, NULL, ?, ?, ?, ?, ?, TRUE
                FROM market_data_source source
                WHERE source.code = ? AND source.enabled = TRUE
                ON CONFLICT (instrument_id, source_id, interval_code, opened_at) DO NOTHING
                """, item.instrumentId(), canonicalTimestamp, canonicalTimestamp,
                item.officialOpen(), item.officialHigh(), item.officialLow(), item.officialClose(),
                item.officialVolume(), SECONDARY_SOURCE_CODE);
        List<StoredCandle> stored = jdbcTemplate.query("""
                SELECT candle.open_price, candle.high_price, candle.low_price,
                       candle.close_price, candle.volume
                FROM market_candle candle
                JOIN market_data_source source ON source.id = candle.source_id
                WHERE candle.instrument_id = ? AND source.code = ? AND candle.interval_code = 'days:1'
                  AND candle.opened_at = ?
                """, (rs, row) -> new StoredCandle(
                rs.getBigDecimal("open_price"), rs.getBigDecimal("high_price"),
                rs.getBigDecimal("low_price"), rs.getBigDecimal("close_price"),
                rs.getBigDecimal("volume")), item.instrumentId(), SECONDARY_SOURCE_CODE, canonicalTimestamp);
        if (stored.size() != 1 || !sameCandle(item, stored.getFirst())) {
            throw new IllegalStateException("Stored NSE BhavCopy candle conflicts with the reviewed plan");
        }
    }

    private boolean validOfficialCandle(PlanItem item) {
        return item.officialOpen() != null && item.officialHigh() != null
                && item.officialLow() != null && item.officialClose() != null
                && item.officialOpen().signum() > 0 && item.officialHigh().signum() > 0
                && item.officialLow().signum() > 0 && item.officialClose().signum() > 0
                && item.officialLow().compareTo(item.officialOpen()) <= 0
                && item.officialLow().compareTo(item.officialClose()) <= 0
                && item.officialHigh().compareTo(item.officialOpen()) >= 0
                && item.officialHigh().compareTo(item.officialClose()) >= 0
                && (item.officialVolume() == null || item.officialVolume().signum() >= 0);
    }

    private boolean sameCandle(PlanItem expected, StoredCandle actual) {
        return sameDecimal(expected.officialOpen(), actual.open())
                && sameDecimal(expected.officialHigh(), actual.high())
                && sameDecimal(expected.officialLow(), actual.low())
                && sameDecimal(expected.officialClose(), actual.close())
                && sameDecimal(expected.officialVolume(), actual.volume());
    }

    boolean sameDecimal(BigDecimal left, BigDecimal right) {
        return left == null ? right == null : right != null && left.compareTo(right) == 0;
    }

    private void markItemFailed(long itemId, RuntimeException exception) {
        jdbcTemplate.update("""
                UPDATE remaining_data_remediation_item
                SET status = 'FAILED', attempts = attempts + 1,
                    last_error_code = ?, last_error_detail = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status <> 'COMPLETED'
                """, limited(exception.getClass().getSimpleName(), 64),
                limited(safeMessage(exception), 1000), itemId);
    }

    private void finishPlan(UUID planId) {
        jdbcTemplate.update("""
                UPDATE remaining_data_remediation_plan plan
                SET status = CASE
                        WHEN EXISTS (
                            SELECT 1 FROM remaining_data_remediation_item item
                            WHERE item.plan_id = plan.id AND item.status = 'FAILED'
                        ) THEN 'PARTIAL_FAILED'
                        WHEN EXISTS (
                            SELECT 1 FROM remaining_data_remediation_item item
                            WHERE item.plan_id = plan.id AND item.status <> 'COMPLETED'
                        ) THEN 'RUNNING'
                        ELSE 'COMPLETED'
                    END,
                    completed_at = CASE
                        WHEN NOT EXISTS (
                            SELECT 1 FROM remaining_data_remediation_item item
                            WHERE item.plan_id = plan.id AND item.status <> 'COMPLETED'
                        ) THEN CURRENT_TIMESTAMP ELSE NULL END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """, planId);
    }

    private RemainingDataRemediationReport report(UUID jobId, String expectedPlanHash) {
        Plan plan = findPlan(jobId);
        if (plan == null || !plan.planHash().equals(expectedPlanHash)) {
            throw new IllegalStateException("The persisted Step 21 plan no longer matches the reviewed hash");
        }
        Counts counts = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) AS total_items,
                       COUNT(*) FILTER (WHERE status = 'PENDING') AS pending_items,
                       COUNT(*) FILTER (WHERE status = 'COMPLETED') AS completed_items,
                       COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_items,
                       COUNT(*) FILTER (WHERE resolution_type = 'SECONDARY_SOURCE_BACKFILLED') AS secondary_items,
                       COUNT(*) FILTER (WHERE resolution_type = 'FEATURE_WINDOW_EXCLUDED') AS exclusion_items,
                       COUNT(*) FILTER (WHERE resolution_type = 'PROVIDER_ADJUSTMENT') AS adjustment_items,
                       COUNT(*) FILTER (WHERE secondary_candle_ready) AS secondary_ready,
                       COUNT(*) FILTER (WHERE resolution_event_id IS NOT NULL) AS resolutions_written
                FROM remaining_data_remediation_item WHERE plan_id = ?
                """, (rs, row) -> new Counts(
                rs.getInt("total_items"), rs.getInt("pending_items"), rs.getInt("completed_items"),
                rs.getInt("failed_items"), rs.getInt("secondary_items"), rs.getInt("exclusion_items"),
                rs.getInt("adjustment_items"), rs.getInt("secondary_ready"),
                rs.getInt("resolutions_written")), plan.id());
        if (counts == null || counts.total() != plan.itemCount()) {
            throw new IllegalStateException("The persisted Step 21 plan item count is inconsistent");
        }
        List<RemainingDataRemediationReport.Failure> failures = jdbcTemplate.query("""
                SELECT symbol, finding_type, finding_date, last_error_code, last_error_detail
                FROM remaining_data_remediation_item
                WHERE plan_id = ? AND status = 'FAILED'
                ORDER BY symbol, finding_date
                """, (rs, row) -> new RemainingDataRemediationReport.Failure(
                rs.getString("symbol"), QualityFindingType.valueOf(rs.getString("finding_type")),
                rs.getDate("finding_date").toLocalDate(), rs.getString("last_error_code"),
                rs.getString("last_error_detail")), plan.id());
        BackfillQualityReport quality = qualityService.audit(jobId, false);
        int currentResolutionCount = resolutionService.current(jobId).size();
        CandleCounts candleCounts = candleCounts(jobId);
        boolean completed = "COMPLETED".equals(plan.status());
        return new RemainingDataRemediationReport(
                jobId, plan.planHash(), plan.status(), counts.total(), counts.pending(), counts.completed(),
                counts.failed(), counts.secondary(), counts.exclusions(), counts.adjustments(),
                counts.secondaryReady(), candleCounts.upstox(), candleCounts.secondary(), candleCounts.allSources(),
                counts.resolutionsWritten(), currentResolutionCount,
                quality.unresolvedFindingCount(), jobService.summary(jobId).workerEnabled(), completed,
                List.copyOf(failures), completed
                ? "All reviewed corrections are durable. Run the final provider spot check before eligibility."
                : "Re-run the same Step 21 command to retry only failed or pending checkpoints.");
    }

    private CandleCounts candleCounts(UUID jobId) {
        return jdbcTemplate.queryForObject("""
                WITH job_instruments AS (
                    SELECT DISTINCT instrument_id FROM historical_backfill_chunk WHERE job_id = ?
                )
                SELECT COUNT(*) FILTER (WHERE source.code = 'UPSTOX') AS upstox_count,
                       COUNT(*) FILTER (WHERE source.code = ?) AS secondary_count,
                       COUNT(*) AS all_source_count
                FROM market_candle candle
                JOIN job_instruments job_instrument ON job_instrument.instrument_id = candle.instrument_id
                JOIN market_data_source source ON source.id = candle.source_id
                WHERE candle.interval_code = 'days:1'
                """, (rs, row) -> new CandleCounts(
                rs.getLong("upstox_count"), rs.getLong("secondary_count"),
                rs.getLong("all_source_count")), jobId, SECONDARY_SOURCE_CODE);
    }

    private Plan findPlan(UUID jobId) {
        List<Plan> plans = jdbcTemplate.query("""
                SELECT id, job_id, plan_hash, status, reviewed_by, item_count
                FROM remaining_data_remediation_plan WHERE job_id = ?
                """, (rs, row) -> mapPlan(rs), jobId);
        return plans.isEmpty() ? null : plans.getFirst();
    }

    private Plan findPlanById(UUID planId) {
        return jdbcTemplate.queryForObject("""
                SELECT id, job_id, plan_hash, status, reviewed_by, item_count
                FROM remaining_data_remediation_plan WHERE id = ?
                """, (rs, row) -> mapPlan(rs), planId);
    }

    private Plan mapPlan(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Plan(rs.getObject("id", UUID.class), rs.getObject("job_id", UUID.class),
                rs.getString("plan_hash"), rs.getString("status"), rs.getString("reviewed_by"),
                rs.getInt("item_count"));
    }

    private PlanItem findPlanItemForUpdate(UUID planId, long itemId) {
        return jdbcTemplate.queryForObject("""
                SELECT id, instrument_id, symbol, finding_type, finding_date, related_date,
                       analysis_status, resolution_type, exclusion_from, exclusion_to,
                       official_open, official_high, official_low, official_close, official_volume,
                       evidence_source, evidence_url, detail, status
                FROM remaining_data_remediation_item
                WHERE plan_id = ? AND id = ?
                FOR UPDATE
                """, (rs, row) -> new PlanItem(
                rs.getLong("id"), rs.getLong("instrument_id"), rs.getString("symbol"),
                QualityFindingType.valueOf(rs.getString("finding_type")),
                rs.getDate("finding_date").toLocalDate(), localDateOrNull(rs.getDate("related_date")),
                rs.getString("analysis_status"), QualityResolutionType.valueOf(rs.getString("resolution_type")),
                localDateOrNull(rs.getDate("exclusion_from")), localDateOrNull(rs.getDate("exclusion_to")),
                rs.getBigDecimal("official_open"), rs.getBigDecimal("official_high"),
                rs.getBigDecimal("official_low"), rs.getBigDecimal("official_close"),
                rs.getBigDecimal("official_volume"), rs.getString("evidence_source"),
                rs.getString("evidence_url"), rs.getString("detail"), rs.getString("status")), planId, itemId);
    }

    private Date dateOrNull(LocalDate value) {
        return value == null ? null : Date.valueOf(value);
    }

    private LocalDate localDateOrNull(Date value) {
        return value == null ? null : value.toLocalDate();
    }

    private String safeMessage(RuntimeException exception) {
        return exception.getMessage() == null ? exception.getClass().getSimpleName() : exception.getMessage();
    }

    private String limited(String value, int maximumLength) {
        if (value == null) {
            return "";
        }
        return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
    }

    private record Plan(
            UUID id,
            UUID jobId,
            String planHash,
            String status,
            String reviewedBy,
            int itemCount
    ) {
    }

    private record InstrumentScope(long id, String listingEvidenceUrl) {
    }

    private record StoredCandle(
            BigDecimal open,
            BigDecimal high,
            BigDecimal low,
            BigDecimal close,
            BigDecimal volume
    ) {
    }

    private record PlanItem(
            long id,
            long instrumentId,
            String symbol,
            QualityFindingType findingType,
            LocalDate findingDate,
            LocalDate relatedDate,
            String analysisStatus,
            QualityResolutionType resolutionType,
            LocalDate exclusionFrom,
            LocalDate exclusionTo,
            BigDecimal officialOpen,
            BigDecimal officialHigh,
            BigDecimal officialLow,
            BigDecimal officialClose,
            BigDecimal officialVolume,
            String evidenceSource,
            String evidenceUrl,
            String detail,
            String status
    ) {
    }

    private record Counts(
            int total,
            int pending,
            int completed,
            int failed,
            int secondary,
            int exclusions,
            int adjustments,
            int secondaryReady,
            int resolutionsWritten
    ) {
    }

    private record CandleCounts(long upstox, long secondary, long allSources) {
    }
}
