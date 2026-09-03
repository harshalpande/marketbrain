package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class HistoricalBackfillJobService {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;
    private final HistoricalBackfillProperties properties;
    private final YearlyBackfillChunkPlanner chunkPlanner;
    private final ExpansionBatchSelector expansionBatchSelector;

    public HistoricalBackfillJobService(
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate,
            HistoricalBackfillProperties properties,
            YearlyBackfillChunkPlanner chunkPlanner,
            ExpansionBatchSelector expansionBatchSelector
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
        this.properties = properties;
        this.chunkPlanner = chunkPlanner;
        this.expansionBatchSelector = expansionBatchSelector;
    }

    public BackfillJobSummary createPilot(int years) {
        if (years < 1 || years > 15) {
            throw new IllegalArgumentException("Pilot years must be between 1 and 15");
        }
        ensureNoActiveJob();
        UUID snapshotId = latestSnapshotId();
        List<ExpansionBatchSelector.Candidate> instruments = pilotInstruments(snapshotId);
        if (instruments.isEmpty()) {
            throw new IllegalStateException("No configured pilot symbols matched the latest NIFTY 500 snapshot");
        }
        LocalDate toDate = LocalDate.now(INDIA).minusDays(1);
        LocalDate fromDate = toDate.minusYears(years).plusDays(1);
        UUID jobId = UUID.randomUUID();

        persistJob(jobId, snapshotId, "PILOT", null, fromDate, toDate, instruments);
        return summary(jobId, "Pilot created. Review it, enable the worker locally, then start it explicitly.");
    }

    public ExpansionBatchCreationResult createNextExpansionBatch(int years, int batchSize) {
        if (years < 1 || years > 15) {
            throw new IllegalArgumentException("Expansion years must be between 1 and 15");
        }
        if (batchSize < 1 || batchSize > properties.maximumExpansionBatchSize()) {
            throw new IllegalArgumentException(
                    "Expansion batch size must be between 1 and " + properties.maximumExpansionBatchSize());
        }
        ensureNoActiveJob();
        UUID snapshotId = latestSnapshotId();
        requireCompletedPilot(snapshotId);
        requireNoPartialFailedExpansion(snapshotId);

        List<ExpansionBatchSelector.Candidate> snapshotInstruments = matchedInstruments(snapshotId);
        Set<Long> completedInstrumentIds = completedExpansionInstrumentIds(snapshotId);
        ExpansionBatchSelector.Selection selection = expansionBatchSelector.select(
                snapshotInstruments, properties.pilotSymbols(), completedInstrumentIds, batchSize);
        if (selection.selected().isEmpty()) {
            throw new IllegalStateException("No remaining matched NIFTY 500 instruments require expansion");
        }

        int batchNumber = nextExpansionBatchNumber(snapshotId);
        LocalDate toDate = LocalDate.now(INDIA).minusDays(1);
        LocalDate fromDate = toDate.minusYears(years).plusDays(1);
        UUID jobId = UUID.randomUUID();
        persistJob(jobId, snapshotId, "EXPANSION", batchNumber, fromDate, toDate, selection.selected());

        BackfillJobSummary job = summary(jobId,
                "Expansion batch created but not started. Review the batch, then enable and start it explicitly.");
        return new ExpansionBatchCreationResult(
                job, batchNumber, selection.selected().size(), selection.remainingAfterBatch(),
                properties.maximumExpansionBatchSize(),
                "Pilot symbols and instruments from completed expansion batches were excluded.");
    }

    public BackfillJobSummary start(UUID jobId) {
        if (!properties.workerEnabled()) {
            throw new IllegalStateException("Backfill worker is disabled in local configuration");
        }
        int updated = jdbcTemplate.update("""
                UPDATE historical_backfill_job
                SET status = 'RUNNING', started_at = COALESCE(started_at, CURRENT_TIMESTAMP),
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = 'CREATED'
                """, jobId);
        if (updated == 0) {
            BackfillJobSummary current = summary(jobId, "Job was not startable from its current state.");
            if (!"RUNNING".equals(current.status())) {
                throw new IllegalStateException("Backfill job is not in CREATED state");
            }
        }
        return summary(jobId, "Backfill job is running in resumable yearly chunks.");
    }

    public BackfillJobSummary pause(UUID jobId) {
        jdbcTemplate.update("""
                UPDATE historical_backfill_job
                SET status = 'PAUSED', connectivity_retry_at = NULL, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status IN ('RUNNING', 'WAITING_FOR_CONNECTIVITY')
                """, jobId);
        return summary(jobId, "No new chunks will be claimed; an in-flight request may still finish.");
    }

    public BackfillJobSummary resume(UUID jobId) {
        if (!properties.workerEnabled()) {
            throw new IllegalStateException("Backfill worker is disabled in local configuration");
        }
        int updated = transactionTemplate.execute(status -> {
            int jobs = jdbcTemplate.update("""
                    UPDATE historical_backfill_job
                    SET status = 'RUNNING', connectivity_retry_at = NULL,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ? AND status IN ('PAUSED', 'WAITING_FOR_CONNECTIVITY')
                    """, jobId);
            if (jobs == 1) {
                jdbcTemplate.update("""
                        UPDATE historical_backfill_chunk
                        SET next_attempt_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE job_id = ? AND status = 'RETRY'
                        """, jobId);
            }
            return jobs;
        });
        if (updated == 0) {
            BackfillJobSummary current = summary(jobId, "Job was not resumable from its current state.");
            if (!"RUNNING".equals(current.status())) {
                throw new IllegalStateException("Backfill job is not in PAUSED or WAITING_FOR_CONNECTIVITY state");
            }
        }
        return summary(jobId, "Backfill job resumed from persisted chunk checkpoints.");
    }

    public BackfillRetryResult retryInvalidDataChunks(UUID jobId) {
        if (!properties.workerEnabled()) {
            throw new IllegalStateException("Backfill worker is disabled in local configuration");
        }
        Integer retriedChunks = transactionTemplate.execute(status -> {
            int reset = jdbcTemplate.update("""
                    UPDATE historical_backfill_chunk
                    SET status = 'PENDING', attempts = 0,
                        accepted_rows = 0, rejected_rows = 0,
                        last_error_code = NULL, next_attempt_at = NULL,
                        started_at = NULL, completed_at = NULL,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE job_id = ? AND status = 'FAILED' AND last_error_code = 'INVALID_DATA'
                    """, jobId);
            if (reset == 0) {
                throw new IllegalStateException("No failed INVALID_DATA chunks exist for this job");
            }
            int reopened = jdbcTemplate.update("""
                    UPDATE historical_backfill_job
                    SET status = 'RUNNING', completed_at = NULL,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ? AND status = 'PARTIAL_FAILED'
                    """, jobId);
            if (reopened == 0) {
                throw new IllegalStateException("Only a PARTIAL_FAILED job can retry invalid-data chunks");
            }
            return reset;
        });
        return new BackfillRetryResult(
                jobId, retriedChunks == null ? 0 : retriedChunks, "RUNNING",
                "Only FAILED chunks with error code INVALID_DATA were reset; all completed checkpoints were retained.");
    }

    public BackfillJobSummary summary(UUID jobId) {
        return summary(jobId, "Backfill progress is calculated from persisted chunk checkpoints.");
    }

    public BackfillJobSummary latestSummary() {
        List<UUID> jobs = jdbcTemplate.query("""
                SELECT id FROM historical_backfill_job ORDER BY created_at DESC LIMIT 1
                """, (rs, row) -> rs.getObject(1, UUID.class));
        if (jobs.isEmpty()) {
            throw new IllegalArgumentException("No historical backfill job exists");
        }
        return summary(jobs.getFirst(), "Latest persisted historical backfill job.");
    }

    public List<BackfillJobInstrumentSummary> instruments(UUID jobId) {
        List<BackfillJobInstrumentSummary> instruments = jdbcTemplate.query("""
                SELECT source_symbol, provider_instrument_key,
                       COUNT(*) AS total_chunks,
                       COUNT(*) FILTER (WHERE status = 'PENDING') AS pending_chunks,
                       COUNT(*) FILTER (WHERE status = 'RUNNING') AS running_chunks,
                       COUNT(*) FILTER (WHERE status = 'RETRY') AS retry_chunks,
                       COUNT(*) FILTER (WHERE status = 'COMPLETED') AS completed_chunks,
                       COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_chunks
                FROM historical_backfill_chunk
                WHERE job_id = ?
                GROUP BY instrument_id, source_symbol, provider_instrument_key
                ORDER BY source_symbol
                """, (rs, row) -> new BackfillJobInstrumentSummary(
                rs.getString("source_symbol"), rs.getString("provider_instrument_key"),
                rs.getInt("total_chunks"), rs.getInt("pending_chunks"), rs.getInt("running_chunks"),
                rs.getInt("retry_chunks"), rs.getInt("completed_chunks"), rs.getInt("failed_chunks")), jobId);
        if (instruments.isEmpty()) {
            throw new IllegalArgumentException("Backfill job was not found or contains no instruments");
        }
        return List.copyOf(instruments);
    }

    private BackfillJobSummary summary(UUID jobId, String detail) {
        List<BackfillJobSummary> results = jdbcTemplate.query("""
                SELECT job.id, job.job_type, job.batch_number, job.status,
                       job.requested_from, job.requested_to,
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
                WHERE job.id = ?
                GROUP BY job.id
                """, (rs, row) -> {
            int total = rs.getInt("total_chunks");
            int completed = rs.getInt("completed_chunks");
            int failed = rs.getInt("failed_chunks");
            double progress = total == 0 ? 0 : Math.round(((completed + failed) * 10000.0) / total) / 100.0;
            return new BackfillJobSummary(
                    rs.getObject("id", UUID.class), rs.getString("job_type"),
                    rs.getObject("batch_number", Integer.class), rs.getString("status"),
                    rs.getDate("requested_from").toLocalDate(), rs.getDate("requested_to").toLocalDate(),
                    rs.getInt("requested_instrument_limit"), total, rs.getInt("pending_chunks"),
                    rs.getInt("running_chunks"), rs.getInt("retry_chunks"), completed, failed,
                    rs.getLong("accepted_rows"), rs.getLong("rejected_rows"), progress,
                    rs.getInt("connectivity_failure_count"), instantOrNull(rs.getTimestamp("connectivity_retry_at")),
                    rs.getString("last_connectivity_error_code"),
                    properties.workerEnabled(), detail);
        }, jobId);
        if (results.isEmpty()) {
            throw new IllegalArgumentException("Backfill job was not found");
        }
        return results.getFirst();
    }

    private UUID latestSnapshotId() {
        List<UUID> snapshots = jdbcTemplate.query("""
                SELECT id FROM universe_snapshot
                WHERE universe_code = 'NIFTY_500'
                ORDER BY observed_on DESC, received_at DESC LIMIT 1
                """, (rs, row) -> rs.getObject(1, UUID.class));
        if (snapshots.isEmpty()) {
            throw new IllegalStateException("Import the current NIFTY 500 snapshot before creating a pilot");
        }
        return snapshots.getFirst();
    }

    private List<ExpansionBatchSelector.Candidate> pilotInstruments(UUID snapshotId) {
        List<ExpansionBatchSelector.Candidate> matched = matchedInstruments(snapshotId);
        Map<String, ExpansionBatchSelector.Candidate> bySymbol = new LinkedHashMap<>();
        for (ExpansionBatchSelector.Candidate instrument : matched) {
            bySymbol.put(instrument.symbol().toUpperCase(Locale.ROOT), instrument);
        }
        List<ExpansionBatchSelector.Candidate> selected = new ArrayList<>();
        for (String configured : properties.pilotSymbols()) {
            ExpansionBatchSelector.Candidate instrument = bySymbol.get(configured.trim().toUpperCase(Locale.ROOT));
            if (instrument != null) {
                selected.add(instrument);
            }
        }
        return List.copyOf(selected);
    }

    private List<ExpansionBatchSelector.Candidate> matchedInstruments(UUID snapshotId) {
        return jdbcTemplate.query("""
                SELECT member.instrument_id, member.provider_instrument_key, member.source_symbol,
                       instrument.listed_on
                FROM universe_snapshot_member member
                JOIN instrument ON instrument.id = member.instrument_id
                WHERE member.snapshot_id = ? AND member.match_status = 'MATCHED'
                """, (rs, row) -> new ExpansionBatchSelector.Candidate(
                rs.getLong("instrument_id"), rs.getString("provider_instrument_key"),
                rs.getString("source_symbol"),
                rs.getDate("listed_on") == null ? null : rs.getDate("listed_on").toLocalDate()), snapshotId);
    }

    private void ensureNoActiveJob() {
        Integer activeJobs = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM historical_backfill_job
                WHERE status IN ('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'PAUSED')
                """, Integer.class);
        if (activeJobs != null && activeJobs > 0) {
            throw new IllegalStateException("Finish or review the existing non-terminal backfill job first");
        }
    }

    private void requireCompletedPilot(UUID snapshotId) {
        Integer completedPilots = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM historical_backfill_job
                WHERE universe_snapshot_id = ? AND job_type = 'PILOT' AND status = 'COMPLETED'
                """, Integer.class, snapshotId);
        if (completedPilots == null || completedPilots == 0) {
            throw new IllegalStateException(
                    "A completed pilot for the latest NIFTY 500 snapshot is required before expansion");
        }
    }

    private void requireNoPartialFailedExpansion(UUID snapshotId) {
        Integer partialFailures = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM historical_backfill_job
                WHERE universe_snapshot_id = ? AND job_type = 'EXPANSION' AND status = 'PARTIAL_FAILED'
                """, Integer.class, snapshotId);
        if (partialFailures != null && partialFailures > 0) {
            throw new IllegalStateException(
                    "Review the partial-failed expansion batch before creating another batch");
        }
    }

    private Set<Long> completedExpansionInstrumentIds(UUID snapshotId) {
        List<Long> ids = jdbcTemplate.query("""
                SELECT DISTINCT chunk.instrument_id
                FROM historical_backfill_chunk chunk
                JOIN historical_backfill_job job ON job.id = chunk.job_id
                WHERE job.universe_snapshot_id = ?
                  AND job.job_type = 'EXPANSION'
                  AND job.status = 'COMPLETED'
                """, (rs, row) -> rs.getLong("instrument_id"), snapshotId);
        return Set.copyOf(new HashSet<>(ids));
    }

    private int nextExpansionBatchNumber(UUID snapshotId) {
        Integer next = jdbcTemplate.queryForObject("""
                SELECT COALESCE(MAX(batch_number), 0) + 1
                FROM historical_backfill_job
                WHERE universe_snapshot_id = ? AND job_type = 'EXPANSION'
                """, Integer.class, snapshotId);
        return next == null ? 1 : next;
    }

    private void persistJob(
            UUID jobId,
            UUID snapshotId,
            String jobType,
            Integer batchNumber,
            LocalDate fromDate,
            LocalDate toDate,
            List<ExpansionBatchSelector.Candidate> instruments
    ) {
        transactionTemplate.executeWithoutResult(status -> {
            jdbcTemplate.update("""
                    INSERT INTO historical_backfill_job
                        (id, universe_snapshot_id, provider_code, interval_code, requested_from,
                         requested_to, requested_instrument_limit, job_type, batch_number, status)
                    VALUES (?, ?, 'UPSTOX', 'days:1', ?, ?, ?, ?, ?, 'CREATED')
                    """, jobId, snapshotId, Date.valueOf(fromDate), Date.valueOf(toDate), instruments.size(),
                    jobType, batchNumber);
            for (ExpansionBatchSelector.Candidate instrument : instruments) {
                LocalDate instrumentFromDate = effectiveFromDate(fromDate, instrument.listedOn());
                for (YearlyBackfillChunkPlanner.DateChunk chunk : chunkPlanner.plan(instrumentFromDate, toDate)) {
                    jdbcTemplate.update("""
                            INSERT INTO historical_backfill_chunk
                                (job_id, instrument_id, provider_instrument_key, source_symbol,
                                 from_date, to_date, status)
                            VALUES (?, ?, ?, ?, ?, ?, 'PENDING')
                            """, jobId, instrument.instrumentId(), instrument.providerInstrumentKey(),
                            instrument.symbol(), Date.valueOf(chunk.fromDate()), Date.valueOf(chunk.toDate()));
                }
            }
        });
    }

    static LocalDate effectiveFromDate(LocalDate requestedFrom, LocalDate listedOn) {
        return listedOn == null || listedOn.isBefore(requestedFrom) ? requestedFrom : listedOn;
    }

    private Instant instantOrNull(Timestamp value) {
        return value == null ? null : value.toInstant();
    }
}
