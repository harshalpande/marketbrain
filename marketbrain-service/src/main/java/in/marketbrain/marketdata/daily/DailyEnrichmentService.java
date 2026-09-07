package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
public class DailyEnrichmentService {

    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;
    private final DailyEnrichmentProperties properties;
    private final HistoricalBackfillProperties backfillProperties;
    private final DailyEnrichmentPlanner planner;

    public DailyEnrichmentService(
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate,
            DailyEnrichmentProperties properties,
            HistoricalBackfillProperties backfillProperties,
            DailyEnrichmentPlanner planner
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
        this.properties = properties;
        this.backfillProperties = backfillProperties;
        this.planner = planner;
    }

    public LocalDate defaultTargetDate() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of(properties.zone()));
        LocalDate target = now.toLocalTime().isBefore(LocalTime.parse(properties.providerWindowStart()))
                ? now.toLocalDate().minusDays(1) : now.toLocalDate();
        while (target.getDayOfWeek().getValue() > 5) {
            target = target.minusDays(1);
        }
        return target;
    }

    public DailyEnrichmentPreview preview(LocalDate targetDate) {
        return withRuntimeConfiguration(buildPlan(requirePermittedTarget(targetDate)).preview());
    }

    public DailyEnrichmentRunSummary create(LocalDate targetDate, String expectedManifestHash) {
        LocalDate permittedTarget = requirePermittedTarget(targetDate);
        requireManifestHashFormat(expectedManifestHash);
        UUID snapshotId = latestSnapshotId();
        List<UUID> existing = existingRun(snapshotId, permittedTarget);
        if (!existing.isEmpty()) {
            DailyEnrichmentRunSummary current = summary(existing.getFirst(),
                    "Existing daily enrichment run for this snapshot and target date.");
            requireManifestHash(expectedManifestHash, current.manifestHash());
            return current;
        }

        DailyEnrichmentPlanner.Plan plan = buildPlan(snapshotId, permittedTarget);
        DailyEnrichmentPreview preview = plan.preview();
        requireManifestHash(expectedManifestHash, preview.manifestHash());
        if (preview.blockedInstruments() > 0) {
            throw new IllegalStateException("Daily enrichment preview contains blocked instruments");
        }
        if (plan.fetchItems().isEmpty()) {
            throw new IllegalStateException("All instruments are already current for the requested target date");
        }

        ensureNoActiveCollectionJob();
        UUID runId = UUID.randomUUID();
        transactionTemplate.executeWithoutResult(status -> {
            jdbcTemplate.update("""
                    INSERT INTO historical_backfill_job
                        (id, universe_snapshot_id, provider_code, interval_code, requested_from,
                         requested_to, requested_instrument_limit, job_type, batch_number,
                         selection_manifest_hash, status)
                    VALUES (?, ?, 'UPSTOX', 'days:1', ?, ?, ?, 'DAILY', NULL, ?, 'CREATED')
                    """, runId, plan.snapshotId(), Date.valueOf(preview.earliestFromDate()),
                    Date.valueOf(preview.targetDate()), plan.fetchItems().size(), preview.manifestHash());
            for (DailyEnrichmentPlanner.PlannedInstrument instrument : plan.fetchItems()) {
                jdbcTemplate.update("""
                        INSERT INTO historical_backfill_chunk
                            (job_id, instrument_id, provider_instrument_key, source_symbol,
                             from_date, to_date, status)
                        VALUES (?, ?, ?, ?, ?, ?, 'PENDING')
                        """, runId, instrument.instrumentId(), instrument.providerInstrumentKey(),
                        instrument.symbol(), Date.valueOf(instrument.requestedFrom()),
                        Date.valueOf(instrument.requestedTo()));
            }
        });
        return summary(runId,
                "Hash-locked daily enrichment run created but not started; raw candles are unchanged.");
    }

    public DailyEnrichmentRunSummary start(UUID runId) {
        if (!backfillProperties.workerEnabled()) {
            throw new IllegalStateException("Backfill worker is disabled in local configuration");
        }
        int updated = jdbcTemplate.update("""
                UPDATE historical_backfill_job
                SET status = 'RUNNING', started_at = COALESCE(started_at, CURRENT_TIMESTAMP),
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND job_type = 'DAILY' AND status = 'CREATED'
                """, runId);
        if (updated == 0) {
            DailyEnrichmentRunSummary current = summary(runId,
                    "Daily enrichment run was not startable from its current state.");
            if (!"RUNNING".equals(current.status())) {
                throw new IllegalStateException("Daily enrichment run is not in CREATED state");
            }
        }
        return summary(runId, "Daily enrichment is running through persisted, resumable chunks.");
    }

    public DailyEnrichmentRunSummary summary(UUID runId) {
        return summary(runId, "Daily enrichment progress from persisted chunk checkpoints.");
    }

    public DailyEnrichmentRunSummary latestSummary() {
        List<UUID> runs = jdbcTemplate.query("""
                SELECT id FROM historical_backfill_job
                WHERE job_type = 'DAILY'
                ORDER BY created_at DESC LIMIT 1
                """, (rs, row) -> rs.getObject(1, UUID.class));
        if (runs.isEmpty()) {
            throw new IllegalArgumentException("No daily enrichment run exists");
        }
        return summary(runs.getFirst(), "Latest persisted daily enrichment run.");
    }

    public Optional<DailyEnrichmentRunSummary> findForTarget(LocalDate targetDate) {
        LocalDate permittedTarget = requirePermittedTarget(targetDate);
        List<UUID> existing = existingRun(latestSnapshotId(), permittedTarget);
        return existing.isEmpty()
                ? Optional.empty()
                : Optional.of(summary(existing.getFirst(), "Daily enrichment run for target date."));
    }

    private DailyEnrichmentPlanner.Plan buildPlan(LocalDate targetDate) {
        return buildPlan(latestSnapshotId(), targetDate);
    }

    private DailyEnrichmentPlanner.Plan buildPlan(UUID snapshotId, LocalDate targetDate) {
        List<DailyEnrichmentPlanner.Candidate> candidates = jdbcTemplate.query("""
                SELECT member.instrument_id, member.provider_instrument_key, member.source_symbol,
                       MAX((candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date)
                           FILTER (WHERE source.code = 'UPSTOX') AS last_stored_date
                FROM universe_snapshot_member member
                LEFT JOIN market_candle candle
                       ON candle.instrument_id = member.instrument_id
                      AND candle.interval_code = 'days:1'
                LEFT JOIN market_data_source source ON source.id = candle.source_id
                WHERE member.snapshot_id = ? AND member.match_status = 'MATCHED'
                GROUP BY member.instrument_id, member.provider_instrument_key, member.source_symbol
                ORDER BY member.source_symbol
                """, (rs, row) -> new DailyEnrichmentPlanner.Candidate(
                rs.getLong("instrument_id"), rs.getString("provider_instrument_key"),
                rs.getString("source_symbol"), rs.getDate("last_stored_date") == null
                        ? null : rs.getDate("last_stored_date").toLocalDate()), snapshotId);
        if (candidates.isEmpty()) {
            throw new IllegalStateException("Latest NIFTY 500 snapshot contains no matched instruments");
        }
        return planner.plan(snapshotId, targetDate, properties.maximumCatchupDays(), candidates);
    }

    private DailyEnrichmentPreview withRuntimeConfiguration(DailyEnrichmentPreview preview) {
        return new DailyEnrichmentPreview(
                preview.universeSnapshotId(), preview.targetDate(), preview.instrumentCount(),
                preview.upToDateInstruments(), preview.fetchInstruments(), preview.blockedInstruments(),
                preview.earliestFromDate(), preview.totalRequestedCalendarDays(),
                preview.maximumCatchupDays(), preview.manifestHash(), preview.databaseWritesPerformed(),
                backfillProperties.workerEnabled(), properties.schedulerEnabled(), properties.cron(),
                properties.finalAttemptCron(), properties.providerWindowStart(), properties.providerWindowCutoff(),
                properties.readinessSymbols().size(), preview.instruments(), preview.detail());
    }

    private List<UUID> existingRun(UUID snapshotId, LocalDate targetDate) {
        return jdbcTemplate.query("""
                SELECT id FROM historical_backfill_job
                WHERE universe_snapshot_id = ? AND requested_to = ? AND job_type = 'DAILY'
                """, (rs, row) -> rs.getObject(1, UUID.class), snapshotId, Date.valueOf(targetDate));
    }

    private LocalDate requirePermittedTarget(LocalDate targetDate) {
        if (targetDate == null) {
            throw new IllegalArgumentException("Target date is required");
        }
        LocalDate today = LocalDate.now(ZoneId.of(properties.zone()));
        if (targetDate.isAfter(today)) {
            throw new IllegalArgumentException("Daily enrichment target date cannot be in the future");
        }
        return targetDate;
    }

    private UUID latestSnapshotId() {
        List<UUID> snapshots = jdbcTemplate.query("""
                SELECT id FROM universe_snapshot
                WHERE universe_code = 'NIFTY_500'
                ORDER BY observed_on DESC, received_at DESC LIMIT 1
                """, (rs, row) -> rs.getObject(1, UUID.class));
        if (snapshots.isEmpty()) {
            throw new IllegalStateException("Import the current NIFTY 500 snapshot before daily enrichment");
        }
        return snapshots.getFirst();
    }

    private void ensureNoActiveCollectionJob() {
        Integer activeJobs = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM historical_backfill_job
                WHERE status IN ('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'PAUSED')
                """, Integer.class);
        if (activeJobs != null && activeJobs > 0) {
            throw new IllegalStateException("Finish or review the existing non-terminal collection job first");
        }
    }

    private void requireManifestHash(String supplied, String expected) {
        requireManifestHashFormat(supplied);
        if (!supplied.equals(expected)) {
            throw new IllegalStateException("Live daily enrichment plan differs from the reviewed manifest hash");
        }
    }

    private void requireManifestHashFormat(String supplied) {
        if (supplied == null || !supplied.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("A lowercase 64-character reviewed manifest hash is required");
        }
    }

    private DailyEnrichmentRunSummary summary(UUID runId, String detail) {
        List<DailyEnrichmentRunSummary> results = jdbcTemplate.query("""
                SELECT job.id, job.status, job.universe_snapshot_id, job.requested_from,
                       job.requested_to, job.selection_manifest_hash,
                       job.requested_instrument_limit,
                       COUNT(chunk.id) AS total_chunks,
                       COUNT(chunk.id) FILTER (WHERE chunk.status = 'PENDING') AS pending_chunks,
                       COUNT(chunk.id) FILTER (WHERE chunk.status = 'RUNNING') AS running_chunks,
                       COUNT(chunk.id) FILTER (WHERE chunk.status = 'RETRY') AS retry_chunks,
                       COUNT(chunk.id) FILTER (WHERE chunk.status = 'COMPLETED') AS completed_chunks,
                       COUNT(chunk.id) FILTER (WHERE chunk.status = 'FAILED') AS failed_chunks,
                       COALESCE(SUM(chunk.accepted_rows), 0) AS accepted_rows,
                       COALESCE(SUM(chunk.rejected_rows), 0) AS rejected_rows,
                       job.connectivity_failure_count, job.connectivity_retry_at,
                       job.last_connectivity_error_code
                FROM historical_backfill_job job
                LEFT JOIN historical_backfill_chunk chunk ON chunk.job_id = job.id
                WHERE job.id = ? AND job.job_type = 'DAILY'
                GROUP BY job.id
                """, (rs, row) -> {
            int total = rs.getInt("total_chunks");
            int completed = rs.getInt("completed_chunks");
            int failed = rs.getInt("failed_chunks");
            double progress = total == 0 ? 0
                    : Math.round(((completed + failed) * 10000.0) / total) / 100.0;
            return new DailyEnrichmentRunSummary(
                    rs.getObject("id", UUID.class), rs.getString("status"),
                    rs.getObject("universe_snapshot_id", UUID.class),
                    rs.getDate("requested_from").toLocalDate(), rs.getDate("requested_to").toLocalDate(),
                    rs.getString("selection_manifest_hash"), rs.getInt("requested_instrument_limit"),
                    total, rs.getInt("pending_chunks"), rs.getInt("running_chunks"),
                    rs.getInt("retry_chunks"), completed, failed, rs.getLong("accepted_rows"),
                    rs.getLong("rejected_rows"), progress, rs.getInt("connectivity_failure_count"),
                    instantOrNull(rs.getTimestamp("connectivity_retry_at")),
                    rs.getString("last_connectivity_error_code"), backfillProperties.workerEnabled(),
                    properties.schedulerEnabled(), detail);
        }, runId);
        if (results.isEmpty()) {
            throw new IllegalArgumentException("Daily enrichment run was not found");
        }
        return results.getFirst();
    }

    private Instant instantOrNull(Timestamp value) {
        return value == null ? null : value.toInstant();
    }
}
