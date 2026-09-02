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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@Service
public class HistoricalBackfillJobService {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;
    private final HistoricalBackfillProperties properties;
    private final YearlyBackfillChunkPlanner chunkPlanner;

    public HistoricalBackfillJobService(
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate,
            HistoricalBackfillProperties properties,
            YearlyBackfillChunkPlanner chunkPlanner
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
        this.properties = properties;
        this.chunkPlanner = chunkPlanner;
    }

    public BackfillJobSummary createPilot(int years) {
        if (years < 1 || years > 15) {
            throw new IllegalArgumentException("Pilot years must be between 1 and 15");
        }
        Integer activeJobs = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM historical_backfill_job
                WHERE status IN ('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'PAUSED')
                """, Integer.class);
        if (activeJobs != null && activeJobs > 0) {
            throw new IllegalStateException("Finish or review the existing non-terminal backfill job first");
        }
        UUID snapshotId = latestSnapshotId();
        List<PilotInstrument> instruments = pilotInstruments(snapshotId);
        if (instruments.isEmpty()) {
            throw new IllegalStateException("No configured pilot symbols matched the latest NIFTY 500 snapshot");
        }
        LocalDate toDate = LocalDate.now(INDIA).minusDays(1);
        LocalDate fromDate = toDate.minusYears(years).plusDays(1);
        UUID jobId = UUID.randomUUID();

        transactionTemplate.executeWithoutResult(status -> {
            jdbcTemplate.update("""
                    INSERT INTO historical_backfill_job
                        (id, universe_snapshot_id, provider_code, interval_code, requested_from,
                         requested_to, requested_instrument_limit, status)
                    VALUES (?, ?, 'UPSTOX', 'days:1', ?, ?, ?, 'CREATED')
                    """, jobId, snapshotId, Date.valueOf(fromDate), Date.valueOf(toDate), instruments.size());
            for (PilotInstrument instrument : instruments) {
                for (YearlyBackfillChunkPlanner.DateChunk chunk : chunkPlanner.plan(fromDate, toDate)) {
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
        return summary(jobId, "Pilot created. Review it, enable the worker locally, then start it explicitly.");
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
        return summary(jobId, "Pilot is running in resumable yearly chunks.");
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
        return summary(jobId, "Pilot resumed from persisted chunk checkpoints.");
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

    private BackfillJobSummary summary(UUID jobId, String detail) {
        List<BackfillJobSummary> results = jdbcTemplate.query("""
                SELECT job.id, job.status, job.requested_from, job.requested_to,
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
                    rs.getObject("id", UUID.class), rs.getString("status"),
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

    private List<PilotInstrument> pilotInstruments(UUID snapshotId) {
        List<PilotInstrument> matched = jdbcTemplate.query("""
                SELECT instrument_id, provider_instrument_key, source_symbol
                FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'MATCHED'
                """, (rs, row) -> new PilotInstrument(
                rs.getLong("instrument_id"), rs.getString("provider_instrument_key"),
                rs.getString("source_symbol")), snapshotId);
        Map<String, PilotInstrument> bySymbol = new LinkedHashMap<>();
        for (PilotInstrument instrument : matched) {
            bySymbol.put(instrument.symbol().toUpperCase(Locale.ROOT), instrument);
        }
        List<PilotInstrument> selected = new ArrayList<>();
        for (String configured : properties.pilotSymbols()) {
            PilotInstrument instrument = bySymbol.get(configured.trim().toUpperCase(Locale.ROOT));
            if (instrument != null) {
                selected.add(instrument);
            }
        }
        return List.copyOf(selected);
    }

    private record PilotInstrument(long instrumentId, String providerInstrumentKey, String symbol) {
    }

    private Instant instantOrNull(Timestamp value) {
        return value == null ? null : value.toInstant();
    }
}
