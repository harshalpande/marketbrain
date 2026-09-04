package in.marketbrain.marketdata.backfill;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
public class QualityResolutionService {

    private final JdbcTemplate jdbcTemplate;
    private final QualityResolutionPolicy policy;

    public QualityResolutionService(JdbcTemplate jdbcTemplate, QualityResolutionPolicy policy) {
        this.jdbcTemplate = jdbcTemplate;
        this.policy = policy;
    }

    @Transactional
    public QualityResolutionRecord resolve(QualityResolutionRequest request) {
        JobScope job = jobScope(request.jobId());
        InstrumentScope instrument = instrumentScope(request.jobId(), request.symbol(), request.findingType());
        validateFindingDate(job, request.findingDate());
        policy.validate(request.findingType(), request.resolutionType(),
                request.findingDate(), request.exclusionFrom(), request.exclusionTo(),
                job.fromDate(), job.toDate());
        requireNoCurrentResolution(request.jobId(), instrumentIdOrNull(instrument), request.findingType(),
                request.findingDate(), request.relatedDate());
        if (request.resolutionType() == QualityResolutionType.SECONDARY_SOURCE_BACKFILLED) {
            requireSecondaryCandle(instrument, request.findingDate());
        }
        if (request.resolutionType() == QualityResolutionType.CORPORATE_ACTION_TRANSITION) {
            requireCorporateAction(instrument, request.findingDate());
        }

        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO market_data_quality_resolution_event
                    (id, job_id, instrument_id, finding_type, finding_date, related_date,
                     event_action, resolution_type, evidence_source, evidence_url, notes, reviewed_by,
                     exclusion_from, exclusion_to)
                VALUES (?, ?, ?, ?, ?, ?, 'RESOLVE', ?, ?, ?, ?, ?, ?, ?)
                """, id, request.jobId(), instrumentIdOrNull(instrument), request.findingType().name(),
                Date.valueOf(request.findingDate()), dateOrNull(request.relatedDate()),
                request.resolutionType().name(), request.evidenceSource().trim(), request.evidenceUrl().trim(),
                request.notes().trim(), request.reviewedBy().trim(), dateOrNull(request.exclusionFrom()),
                dateOrNull(request.exclusionTo()));
        return findEvent(id);
    }

    @Transactional
    public void revoke(QualityResolutionRevocationRequest request) {
        JobScope job = jobScope(request.jobId());
        InstrumentScope instrument = instrumentScope(request.jobId(), request.symbol(), request.findingType());
        validateFindingDate(job, request.findingDate());
        requireCurrentResolution(request.jobId(), instrumentIdOrNull(instrument), request.findingType(),
                request.findingDate(), request.relatedDate());
        jdbcTemplate.update("""
                INSERT INTO market_data_quality_resolution_event
                    (id, job_id, instrument_id, finding_type, finding_date, related_date,
                     event_action, resolution_type, evidence_source, evidence_url, notes, reviewed_by)
                VALUES (?, ?, ?, ?, ?, ?, 'REVOKE', NULL, ?, ?, ?, ?)
                """, UUID.randomUUID(), request.jobId(), instrumentIdOrNull(instrument),
                request.findingType().name(), Date.valueOf(request.findingDate()),
                dateOrNull(request.relatedDate()), request.evidenceSource().trim(), request.evidenceUrl().trim(),
                request.notes().trim(), request.reviewedBy().trim());
    }

    public List<QualityResolutionRecord> current(UUID jobId) {
        jobScope(jobId);
        return jdbcTemplate.query("""
                SELECT resolution.id, resolution.job_id, instrument.symbol, resolution.finding_type,
                       resolution.finding_date, resolution.related_date, resolution.resolution_type,
                       resolution.allows_training, resolution.evidence_source, resolution.evidence_url,
                       resolution.notes, resolution.reviewed_by, resolution.exclusion_from,
                       resolution.exclusion_to, resolution.created_at
                FROM current_market_data_quality_resolution resolution
                LEFT JOIN instrument ON instrument.id = resolution.instrument_id
                WHERE resolution.job_id = ?
                ORDER BY resolution.finding_date, instrument.symbol, resolution.finding_type
                """, (rs, row) -> mapResolution(rs), jobId);
    }

    private void requireSecondaryCandle(InstrumentScope instrument, LocalDate findingDate) {
        if (instrument == null) {
            throw new IllegalArgumentException("SECONDARY_SOURCE_BACKFILLED requires an instrument symbol");
        }
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM market_candle candle
                JOIN market_data_source source ON source.id = candle.source_id
                WHERE candle.instrument_id = ? AND candle.interval_code = 'days:1'
                  AND source.code <> 'UPSTOX'
                  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date = ?
                """, Integer.class, instrument.id(), Date.valueOf(findingDate));
        if (count == null || count == 0) {
            throw new IllegalStateException("No approved secondary-source candle exists for this finding date");
        }
    }

    private void requireCorporateAction(InstrumentScope instrument, LocalDate findingDate) {
        if (instrument == null) {
            throw new IllegalArgumentException("CORPORATE_ACTION_TRANSITION requires an instrument symbol");
        }
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM corporate_action_event
                WHERE instrument_id = ? AND effective_on = ?
                """, Integer.class, instrument.id(), Date.valueOf(findingDate));
        if (count == null || count == 0) {
            throw new IllegalStateException(
                    "Sync and inspect corporate-action evidence before resolving this finding");
        }
    }

    private void requireCurrentResolution(
            UUID jobId,
            Long instrumentId,
            QualityFindingType findingType,
            LocalDate findingDate,
            LocalDate relatedDate
    ) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM current_market_data_quality_resolution
                WHERE job_id = ? AND finding_type = ? AND finding_date = ?
                  AND instrument_id IS NOT DISTINCT FROM ?
                  AND related_date IS NOT DISTINCT FROM ?
                """, Integer.class, jobId, findingType.name(), Date.valueOf(findingDate),
                instrumentId, dateOrNull(relatedDate));
        if (count == null || count == 0) {
            throw new IllegalStateException("No current resolution exists for this finding");
        }
    }

    private void requireNoCurrentResolution(
            UUID jobId,
            Long instrumentId,
            QualityFindingType findingType,
            LocalDate findingDate,
            LocalDate relatedDate
    ) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM current_market_data_quality_resolution
                WHERE job_id = ? AND finding_type = ? AND finding_date = ?
                  AND instrument_id IS NOT DISTINCT FROM ?
                  AND related_date IS NOT DISTINCT FROM ?
                """, Integer.class, jobId, findingType.name(), Date.valueOf(findingDate),
                instrumentId, dateOrNull(relatedDate));
        rejectExistingCurrentResolution(count);
    }

    void rejectExistingCurrentResolution(Integer count) {
        if (count != null && count > 0) {
            throw new IllegalStateException(
                    "A current resolution already exists for this finding; revoke it before replacing it");
        }
    }

    private JobScope jobScope(UUID jobId) {
        List<JobScope> jobs = jdbcTemplate.query("""
                SELECT requested_from, requested_to, status
                FROM historical_backfill_job WHERE id = ?
                """, (rs, row) -> new JobScope(
                rs.getDate("requested_from").toLocalDate(), rs.getDate("requested_to").toLocalDate(),
                rs.getString("status")), jobId);
        if (jobs.isEmpty()) {
            throw new IllegalArgumentException("Backfill job was not found");
        }
        JobScope job = jobs.getFirst();
        if (!List.of("COMPLETED", "PARTIAL_FAILED").contains(job.status())) {
            throw new IllegalStateException("Only a finished backfill job can be reviewed");
        }
        return job;
    }

    private InstrumentScope instrumentScope(UUID jobId, String symbol, QualityFindingType findingType) {
        if (symbol == null || symbol.isBlank()) {
            if (findingType == QualityFindingType.OFFICIAL_SPECIAL_SESSION) {
                return null;
            }
            throw new IllegalArgumentException("An instrument symbol is required for " + findingType);
        }
        List<InstrumentScope> instruments = jdbcTemplate.query("""
                SELECT DISTINCT instrument.id, instrument.symbol
                FROM historical_backfill_chunk chunk
                JOIN instrument ON instrument.id = chunk.instrument_id
                WHERE chunk.job_id = ? AND UPPER(instrument.symbol) = UPPER(?)
                """, (rs, row) -> new InstrumentScope(rs.getLong("id"), rs.getString("symbol")), jobId, symbol);
        if (instruments.isEmpty()) {
            throw new IllegalArgumentException("Symbol is not part of the backfill job: " + symbol);
        }
        return instruments.getFirst();
    }

    private void validateFindingDate(JobScope job, LocalDate findingDate) {
        if (findingDate.isBefore(job.fromDate()) || findingDate.isAfter(job.toDate())) {
            throw new IllegalArgumentException("Finding date is outside the backfill job window");
        }
    }

    private QualityResolutionRecord findEvent(UUID id) {
        return jdbcTemplate.queryForObject("""
                SELECT event.id, event.job_id, instrument.symbol, event.finding_type,
                       event.finding_date, event.related_date, event.resolution_type,
                       event.resolution_type IN (
                           'VERIFIED_EXCHANGE_MOVE', 'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT',
                           'FEATURE_WINDOW_EXCLUDED', 'SECONDARY_SOURCE_BACKFILLED'
                       ) AS allows_training,
                       event.evidence_source, event.evidence_url, event.notes, event.reviewed_by,
                       event.exclusion_from, event.exclusion_to, event.created_at
                FROM market_data_quality_resolution_event event
                LEFT JOIN instrument ON instrument.id = event.instrument_id
                WHERE event.id = ?
                """, (rs, row) -> mapResolution(rs), id);
    }

    private QualityResolutionRecord mapResolution(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new QualityResolutionRecord(
                rs.getObject("id", UUID.class), rs.getObject("job_id", UUID.class), rs.getString("symbol"),
                QualityFindingType.valueOf(rs.getString("finding_type")),
                rs.getDate("finding_date").toLocalDate(), localDateOrNull(rs.getDate("related_date")),
                QualityResolutionType.valueOf(rs.getString("resolution_type")),
                rs.getBoolean("allows_training"), rs.getString("evidence_source"),
                rs.getString("evidence_url"), rs.getString("notes"), rs.getString("reviewed_by"),
                localDateOrNull(rs.getDate("exclusion_from")), localDateOrNull(rs.getDate("exclusion_to")),
                rs.getTimestamp("created_at").toInstant());
    }

    private Long instrumentIdOrNull(InstrumentScope instrument) {
        return instrument == null ? null : instrument.id();
    }

    private Date dateOrNull(LocalDate value) {
        return value == null ? null : Date.valueOf(value);
    }

    private LocalDate localDateOrNull(Date value) {
        return value == null ? null : value.toLocalDate();
    }

    private record JobScope(LocalDate fromDate, LocalDate toDate, String status) {
    }

    private record InstrumentScope(long id, String symbol) {
    }
}
