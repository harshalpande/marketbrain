package in.marketbrain.feature;

import in.marketbrain.marketdata.backfill.BackfillQualityReport;
import in.marketbrain.marketdata.backfill.BackfillQualityService;
import in.marketbrain.marketdata.backfill.QualityFindingType;
import in.marketbrain.marketdata.backfill.QualityResolutionType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** Deliberately incident-bound. Not a general retry or quality override API. */
@Service
public class ReviewedFeatureReconciliationService {
    static final LocalDate DATE = LocalDate.of(2026, 10, 8);
    static final UUID DAILY = UUID.fromString("eebff875-3621-4064-a2ea-9de0b269681e");
    static final UUID SNAPSHOT = UUID.fromString("fc15cbe7-15c7-46ab-989e-f09ba7978858");
    static final UUID UNIVERSE = UUID.fromString("68117add-3ebe-4681-82fc-ff5613ecd869");
    static final UUID RESOLUTION = UUID.fromString("19bc5ced-9ec0-497b-a2d2-ff86768249cd");
    static final String MANIFEST = "50e0749dfdfbc3e370f4cd5d0f23069021154bf69baafcc815cffcb509cbbb62";
    static final String DAILY_MANIFEST = "655ea0fdf52cd86fc68d825d2fb2146e1e14da255c8257edd9b8e2bc941364ee";
    static final String EVIDENCE = "128C921E4C21734E9CC0801B39735ECDF9152A43C9906FB3695FEE44ACB62324";
    private final JdbcTemplate jdbc;
    private final FeatureSnapshotService snapshots;
    private final BackfillQualityService quality;

    public ReviewedFeatureReconciliationService(JdbcTemplate jdbc, FeatureSnapshotService snapshots,
                                                BackfillQualityService quality) {
        this.jdbc = jdbc; this.snapshots = snapshots; this.quality = quality;
    }

    public record Request(String evidenceSha256, String reviewedBy) { }
    public record Result(String version, String status, LocalDate targetDate, UUID dailyRunId,
                         UUID featureSnapshotRunId, String featureManifestHash, UUID reconciliationId,
                         String reviewedBy, String evidenceSha256, String automationStatus,
                         int eligibleCount, int withheldCount, String completionNotificationStatus,
                         boolean databaseWritesPerformed, int snapshotWrites, int signalsCreated,
                         int ordersCreated, String detail) { }
    record Row(String status, UUID snapshotId, String manifest, Integer eligible, Integer withheld,
               String error, int attempts, String warningStatus, String completionStatus) { }
    record Audit(UUID id, UUID dailyId, UUID snapshotId, String manifest, String evidence, String reviewer) { }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ, timeout = 180)
    public Result preview() { return reconcile(null, false); }

    @Transactional(isolation = Isolation.REPEATABLE_READ, timeout = 180)
    public Result apply(Request request) {
        if (request == null || !EVIDENCE.equals(request.evidenceSha256()) || request.reviewedBy() == null
                || request.reviewedBy().isBlank() || request.reviewedBy().trim().length() > 120
                || request.reviewedBy().trim().matches("(?i)^(RESOLVE|PERSIST|RECONCILE|CONFIRM|YES|IDLE)(\\s.*)?$")) {
            throw new IllegalArgumentException("Exact accepted evidence and an actual reviewer name are required.");
        }
        return reconcile(request.reviewedBy().trim(), true);
    }

    private Result reconcile(String reviewer, boolean apply) {
        // Indexed unique target/date and PK joins. The lock serializes this operation with another apply.
        // REPEATABLE_READ checks one consistent DB view; it does not authorize concurrent data repair.
        List<Row> rows = jdbc.query("""
                SELECT a.status, a.feature_snapshot_run_id, a.feature_manifest_hash,
                       a.eligible_count, a.withheld_count, a.last_error_code, a.attempts,
                       (SELECT delivery_status FROM daily_enrichment_notification
                        WHERE target_date=a.target_date AND notice_kind='FEATURE_WARNING') warning_status,
                       (SELECT delivery_status FROM daily_enrichment_notification
                        WHERE target_date=a.target_date AND notice_kind='FEATURE_COMPLETION') completion_status
                FROM daily_feature_snapshot_automation a
                JOIN historical_backfill_job j ON j.id=a.daily_run_id
                JOIN feature_snapshot_run f ON f.id=?
                WHERE a.target_date=? AND a.daily_run_id=? AND j.job_type='DAILY' AND j.status='COMPLETED'
                  AND j.requested_from=DATE '2026-09-19' AND j.requested_to=a.target_date
                  AND j.selection_manifest_hash=? AND j.universe_snapshot_id=?
                  AND f.universe_snapshot_id=j.universe_snapshot_id AND f.requested_as_of=a.target_date
                  AND f.status='COMPLETED' AND f.feature_set_version='TECHNICAL_V1'
                  AND f.source_manifest_hash=? AND f.instrument_count=500
                  AND f.persisted_feature_count=487 AND f.withheld_count=13
                """ + (apply ? " FOR UPDATE OF a NOWAIT" : ""),
                (rs, n) -> new Row(rs.getString("status"), rs.getObject("feature_snapshot_run_id", UUID.class),
                        rs.getString("feature_manifest_hash"), rs.getObject("eligible_count", Integer.class),
                        rs.getObject("withheld_count", Integer.class), rs.getString("last_error_code"),
                        rs.getInt("attempts"), rs.getString("warning_status"), rs.getString("completion_status")),
                SNAPSHOT, DATE, DAILY, DAILY_MANIFEST, UNIVERSE, MANIFEST);
        require(rows.size() == 1, "Reviewed daily/snapshot scope is missing or changed.");
        Row row = rows.getFirst();
        require(MANIFEST.equals(row.manifest()) && Integer.valueOf(487).equals(row.eligible())
                && Integer.valueOf(13).equals(row.withheld()) && row.attempts() == 1
                && "SENT".equals(row.warningStatus()), "Automation checkpoint or warning history changed.");
        List<Audit> audits = jdbc.query("""
                SELECT id, daily_run_id, feature_snapshot_run_id, feature_manifest_hash, evidence_sha256, reviewed_by
                FROM reviewed_feature_reconciliation WHERE target_date=?
                """, (rs, n) -> new Audit(rs.getObject("id", UUID.class), rs.getObject("daily_run_id", UUID.class),
                rs.getObject("feature_snapshot_run_id", UUID.class), rs.getString("feature_manifest_hash"),
                rs.getString("evidence_sha256"), rs.getString("reviewed_by")), DATE);
        require(audits.size() <= 1, "Unexpected reconciliation audit count.");
        Audit audit = audits.isEmpty() ? null : audits.getFirst();
        if ("COMPLETED".equals(row.status())) {
            require(SNAPSHOT.equals(row.snapshotId()) && row.error() == null && audit != null
                    && DAILY.equals(audit.dailyId()) && SNAPSHOT.equals(audit.snapshotId())
                    && MANIFEST.equals(audit.manifest()) && EVIDENCE.equals(audit.evidence())
                    && (reviewer == null || reviewer.equals(audit.reviewer())), "Completed checkpoint lacks matching audit.");
        } else {
            require("REVIEW_REQUIRED".equals(row.status()) && "DATABASE_QUALITY".equals(row.error())
                    && row.snapshotId() == null && audit == null && row.completionStatus() == null,
                    "Only the original stopped review checkpoint may be reconciled.");
        }
        verifyQuality(snapshots.quality(SNAPSHOT, MANIFEST), quality.audit(DAILY, false));
        if (audit != null) { return result("ALREADY_RECONCILED", row, audit, false); }
        if (!apply) { return result("READY_TO_RECONCILE", row, null, false); }

        UUID id = UUID.randomUUID();
        int saved = jdbc.update("""
                INSERT INTO reviewed_feature_reconciliation
                    (id, target_date, daily_run_id, feature_snapshot_run_id, feature_manifest_hash,
                     evidence_sha256, reviewed_by, previous_status, previous_error_code, previous_attempts,
                     previous_completed_at, previous_updated_at)
                SELECT ?, target_date, daily_run_id, ?, feature_manifest_hash, ?, ?, status,
                       last_error_code, attempts, completed_at, updated_at
                FROM daily_feature_snapshot_automation
                WHERE target_date=? AND daily_run_id=? AND status='REVIEW_REQUIRED'
                  AND last_error_code='DATABASE_QUALITY' AND feature_snapshot_run_id IS NULL
                """, id, SNAPSHOT, EVIDENCE, reviewer, DATE, DAILY);
        require(saved == 1, "Audit insert did not affect exactly one row.");
        int updated = jdbc.update("""
                UPDATE daily_feature_snapshot_automation
                SET status='COMPLETED', feature_snapshot_run_id=?, last_error_code=NULL,
                    completed_at=CURRENT_TIMESTAMP, updated_at=CURRENT_TIMESTAMP
                WHERE target_date=? AND daily_run_id=? AND status='REVIEW_REQUIRED'
                  AND last_error_code='DATABASE_QUALITY' AND feature_snapshot_run_id IS NULL
                  AND feature_manifest_hash=? AND eligible_count=487 AND withheld_count=13 AND attempts=1
                """, SNAPSHOT, DATE, DAILY, MANIFEST);
        require(updated == 1, "Automation update did not affect exactly one row; transaction must roll back.");
        // No fanout in transaction; existing scheduler discovers COMPLETED after commit and uses its durable notice ledger.
        return result("RECONCILED", new Row("COMPLETED", SNAPSHOT, MANIFEST, 487, 13, null, 1,
                row.warningStatus(), null), new Audit(id, DAILY, SNAPSHOT, MANIFEST, EVIDENCE, reviewer), true);
    }

    static void verifyQuality(FeatureSnapshotQuality q, BackfillQualityReport d) {
        require(q != null && "ELIGIBLE".equals(q.status()) && SNAPSHOT.equals(q.runId())
                && DATE.equals(q.requestedAsOf()) && "TECHNICAL_V1".equals(q.featureSetVersion())
                && MANIFEST.equals(q.sourceManifestHash()) && MANIFEST.equals(q.recomputedManifestHash())
                && q.instrumentCount()==500 && q.persistedItemCount()==500 && q.persistedFeatureCount()==487
                && q.completeVectorCount()==487 && q.withheldCount()==13 && q.insufficientHistoryCount()==13
                && q.staleCount()==0 && q.noEligibleDataCount()==0 && q.partialVectorViolationCount()==0
                && q.withheldVectorViolationCount()==0 && q.manifestMatches() && !q.databaseWritesPerformed(),
                "Stored snapshot quality changed.");
        require(d != null && DAILY.equals(d.jobId()) && "COMPLETED".equals(d.jobStatus())
                && "PASS".equals(d.qualityStatus()) && DATE.equals(d.requestedTo())
                && LocalDate.of(2026,9,19).equals(d.requestedFrom()) && d.instrumentCount()==500
                && !d.providerSpotCheckRequested() && d.blockingInstrumentCount()==0
                && d.missingProviderDataInstrumentCount()==0 && d.reviewInstrumentCount()==0
                && d.duplicateRows()==0 && d.invalidRows()==0 && d.unresolvedFindingCount()==0
                && d.truncatedFindingCount()==0 && d.currentResolutions()!=null
                && d.currentResolutions().stream().filter(r -> RESOLUTION.equals(r.id()) && DAILY.equals(r.jobId())
                    && "POLICYBZR".equals(r.symbol()) && r.findingType()==QualityFindingType.LARGE_MOVE
                    && LocalDate.of(2026,9,24).equals(r.findingDate()) && r.relatedDate()==null
                    && r.resolutionType()==QualityResolutionType.VERIFIED_EXCHANGE_MOVE
                    && r.exclusionFrom()==null && r.exclusionTo()==null).count()==1,
                "Current daily quality/resolution no longer matches the accepted scope.");
    }

    private Result result(String status, Row row, Audit audit, boolean writes) {
        return new Result("REVIEWED_FEATURE_RECONCILIATION_V1", status, DATE, DAILY, SNAPSHOT, MANIFEST,
                audit == null ? null : audit.id(), audit == null ? null : audit.reviewer(), EVIDENCE,
                row.status(), 487, 13, row.completionStatus(), writes, 0, 0, 0,
                "Checkpoint reconciliation only; no feature regeneration or trading release. Warning retained. "
                        + "After commit the normal notifier may deliver a separate feature-completion notice; delivery is not guaranteed by this response.");
    }
    private static void require(boolean condition, String message) { if (!condition) throw new IllegalStateException(message); }
}
