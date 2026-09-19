package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.*;

/** Read-only evidence linkage, never an adjustment engine or a fresh quality certification. */
@Service
public class NumericalPriceEvidenceService {
    static final String JOBS_SQL = """
            SELECT id, job_type, status, requested_from, requested_to
            FROM historical_backfill_job WHERE interval_code = 'days:1'
              AND requested_from <= ? AND requested_to >= ?
            ORDER BY created_at DESC, id DESC LIMIT 21
            """;
    static final String ACTIONS_SQL = """
            SELECT id, action_type, effective_on, announced_on, amount, ratio, received_at,
                   event_fingerprint, (source_url IS NOT NULL AND source_url <> '') AS has_source_reference
            FROM corporate_action_event WHERE instrument_id = ? AND effective_on BETWEEN ? AND ?
            ORDER BY effective_on, id LIMIT 501
            """;
    private static final Set<UUID> REVIEWED_JOBS = Set.of(
            UUID.fromString("e1d9ea5d-fcb2-4a81-b839-c154bb602243"),
            UUID.fromString("7e8a79ec-045c-4474-b3e8-78e716e11143"),
            UUID.fromString("66826ff9-1aa0-4f13-980b-8e6ed9693301"),
            UUID.fromString("30d59236-017c-406c-bc31-ef4bb1d4ee47"));
    private final JdbcTemplate jdbc;
    public NumericalPriceEvidenceService(JdbcTemplate jdbc) { this.jdbc=jdbc; }

    @Transactional(readOnly=true,timeout=45,isolation=Isolation.REPEATABLE_READ)
    public Evidence inspect(UUID runId, LocalDate from, int offset, int limit) {
        return inspectWindow(runId,from,null,offset,limit);
    }
    @Transactional(readOnly=true,timeout=45,isolation=Isolation.REPEATABLE_READ)
    public Evidence inspectThrough(UUID runId, LocalDate from, LocalDate through, int offset, int limit) {
        if(through==null)throw new IllegalArgumentException("Explicit outcome through-date required.");
        return inspectWindow(runId,from,through,offset,limit);
    }
    private Evidence inspectWindow(UUID runId, LocalDate from, LocalDate requestedThrough, int offset, int limit) {
        if(runId==null || runId.equals(new UUID(0,0)) || from==null || offset<0 || offset>499 || limit<1 || limit>4)
            throw new IllegalArgumentException("Explicit run/from required; offset 0..499, limit 1..4.");
        var runs=jdbc.query(NumericalHistoryCoverageService.RUN_SQL,s->{s.setObject(1,runId);s.setQueryTimeout(3);},
                (r,n)->new NumericalHistoryCoverageService.Run(r.getObject("as_of",LocalDate.class),r.getString("dataset_manifest_hash"),r.getInt("instrument_count")));
        if(runs.size()!=1) throw new IllegalArgumentException("Completed run not found.");
        var run=runs.getFirst();
        if(run.asOf()==null || run.count()<1 || run.count()>500 || offset>=run.count() || run.manifest()==null || run.manifest().isBlank())
            throw new IllegalStateException("Invalid run metadata.");
        if(from.isBefore(run.asOf().minusDays(729)) || from.isAfter(run.asOf()))
            throw new IllegalArgumentException("Feature scope must be within the run's 730-day historical window.");
        var through=requestedThrough==null?run.asOf():requestedThrough;
        if(through.isBefore(run.asOf()) || through.isAfter(run.asOf().plusDays(45)))
            throw new IllegalArgumentException("Evidence through-date must be as-of through as-of + 45 days.");
        var items=jdbc.query(NumericalFeatureSnapshotService.ITEMS_SQL,s->{s.setObject(1,runId);s.setInt(2,limit);s.setInt(3,offset);s.setQueryTimeout(3);},
                (r,n)->new NumericalFeatureSnapshotService.Item(r.getLong("instrument_id"),r.getString("symbol")));
        if(items.size()!=Math.min(limit,run.count()-offset) || items.stream().map(NumericalFeatureSnapshotService.Item::id).distinct().count()!=items.size())
            throw new IllegalStateException("Selected item scope mismatch.");
        var jobs=jdbc.query(JOBS_SQL,s->{s.setObject(1,through);s.setObject(2,from);s.setQueryTimeout(3);},
                (r,n)->new Job(r.getObject("id",UUID.class),r.getString("job_type"),r.getString("status"),
                        r.getObject("requested_from",LocalDate.class),r.getObject("requested_to",LocalDate.class)));
        boolean jobsCapped=jobs.size()>20;
        var inspectedJobs=jobs.stream().limit(20).toList();
        var results=new ArrayList<Instrument>();
        for(var item:items) {
            var actions=jdbc.query(ACTIONS_SQL,s->{s.setLong(1,item.id());s.setObject(2,from);s.setObject(3,through);s.setQueryTimeout(3);},
                    (r,n)->new Action(r.getLong("id"),r.getString("action_type"),r.getObject("effective_on",LocalDate.class),
                            r.getObject("announced_on",LocalDate.class),r.getBigDecimal("amount"),r.getString("ratio"),
                            instant(r.getTimestamp("received_at")),r.getString("event_fingerprint"),r.getBoolean("has_source_reference")));
            List<Chunk> chunks=List.of(); List<ResolutionEvent> events=List.of();
            if(!inspectedJobs.isEmpty()) {
                String slots=String.join(",",Collections.nCopies(inspectedJobs.size(),"?"));
                String chunkSql="SELECT job_id, from_date, to_date, status, accepted_rows, rejected_rows FROM historical_backfill_chunk "
                        +"WHERE job_id IN ("+slots+") AND instrument_id = ? "
                        +"ORDER BY job_id, from_date, to_date, id LIMIT 201";
                chunks=jdbc.query(chunkSql,s->{int p=1;for(var job:inspectedJobs)s.setObject(p++,job.id());s.setLong(p,item.id());s.setQueryTimeout(3);},
                        (r,n)->new Chunk(r.getObject("job_id",UUID.class),r.getObject("from_date",LocalDate.class),
                                r.getObject("to_date",LocalDate.class),r.getString("status"),r.getInt("accepted_rows"),r.getInt("rejected_rows")));
                // Do not filter RESOLVE/date before latest-event selection: a newer REVOKE must win.
                String eventSql="SELECT id, job_id, instrument_id, finding_type, finding_date, related_date, event_action, "
                        +"resolution_type, exclusion_from, exclusion_to, created_at FROM market_data_quality_resolution_event "
                        +"WHERE job_id IN ("+slots+") AND (instrument_id = ? OR instrument_id IS NULL) "
                        +"ORDER BY created_at DESC, id DESC LIMIT 1001";
                events=jdbc.query(eventSql,s->{int p=1;for(var job:inspectedJobs)s.setObject(p++,job.id());s.setLong(p,item.id());s.setQueryTimeout(3);},
                        (r,n)->new ResolutionEvent(r.getObject("id",UUID.class),r.getObject("job_id",UUID.class),r.getObject("instrument_id",Long.class),
                                r.getString("finding_type"),r.getObject("finding_date",LocalDate.class),r.getObject("related_date",LocalDate.class),
                                r.getString("event_action"),r.getString("resolution_type"),r.getObject("exclusion_from",LocalDate.class),
                                r.getObject("exclusion_to",LocalDate.class),instant(r.getTimestamp("created_at"))));
            }
            var memberJobs=chunks.stream().map(Chunk::jobId).collect(java.util.stream.Collectors.toSet());
            boolean partial=jobsCapped || chunks.size()>200 || events.size()>1000 || actions.size()>500;
            var capturedChunks=chunks;
            var links=inspectedJobs.stream().filter(j->memberJobs.contains(j.id())).map(j->new JobLink(j,
                    REVIEWED_JOBS.contains(j.id())?"E35_PREVIOUS_SAVED_FINAL_REPORT_REVIEW":"SAVED_FINAL_REPORT_NOT_LINKED",
                    !partial && covers(capturedChunks.stream().filter(c->c.jobId().equals(j.id())).toList(),from,through))).toList();
            var ledger=latestRelevant(events,item.id(),memberJobs,from,through);
            int exclusionCount=(int)ledger.stream().filter(e->"RESOLVE".equals(e.eventAction()) && overlaps(e.exclusionFrom(),e.exclusionTo(),from,through)).count();
            int revoked=(int)ledger.stream().filter(e->"REVOKE".equals(e.eventAction())).count();
            var gates=new ArrayList<String>();
            if(partial)gates.add("PARTIAL_CAPPED_EVIDENCE");
            if(links.isEmpty())gates.add("NO_OVERLAPPING_BACKFILL_MEMBERSHIP_FOUND");
            if(links.stream().noneMatch(l->l.completedChunkRangeCoversScope() && "COMPLETED".equals(l.job().status()) && REVIEWED_JOBS.contains(l.job().id())))gates.add("REVIEWED_FINAL_JOB_COVERAGE_NOT_ESTABLISHED");
            if(exclusionCount>0)gates.add("CURRENT_EXCLUSION_OVERLAPS_SCOPE");
            if(revoked>0)gates.add("REVOKED_FINDINGS_REQUIRE_REVIEW");
            gates.add(actions.isEmpty()?"CORPORATE_ACTION_COVERAGE_UNKNOWN":"STORED_CORPORATE_ACTIONS_REQUIRE_PRICE_POLICY_REVIEW");
            gates.add("NO_VERIFIED_ADJUSTMENT_FACTORS_OR_EXECUTABLE_PRICE_BINDING");
            results.add(new Instrument(item.id(),item.symbol(),partial,links,chunks,actions,events.size(),ledger,exclusionCount,revoked,List.copyOf(gates)));
        }
        return new Evidence("NUMERICAL_PRICE_EVIDENCE_V1","PRICE_POLICY_REVIEW_REQUIRED",runId,run.manifest(),from,through,offset,limit,
                jobs.size(),jobsCapped,List.copyOf(results),results.stream().anyMatch(Instrument::partial),false,false,0,0,0,
                "Explicit bounded evidence period only; not certification of executable labels. Links establish stored job/chunk membership, not fresh quality PASS. "
                        +"E35 references prior report review, not immutable candle provenance; completed range is scheduling coverage, not per-session data validation. "
                        +"Only up to 20 overlapping jobs are inspected. Resolution ledger is current, not historical; out-of-scope jobs are not audited. "
                        +"No stored actions does not mean no actions occurred. No unresolved-finding inventory or provider adjustment factors certified. "
                        +"No raw notes, reviewer identities or evidence URLs exported. No candle/price adjustments, labels, training or orders performed.");
    }
    private static Instant instant(Timestamp value){return value==null?null:value.toInstant();}
    static boolean overlaps(LocalDate a,LocalDate b,LocalDate from,LocalDate to){return a!=null && b!=null && !a.isAfter(to) && !b.isBefore(from);}
    static boolean covers(List<Chunk> chunks,LocalDate from,LocalDate to) {
        LocalDate next=from;
        for(var c:chunks.stream().filter(c->"COMPLETED".equals(c.status()) && c.rejectedRows()==0).sorted(Comparator.comparing(Chunk::from)).toList()) {
            if(c.to().isBefore(next))continue;
            if(c.from().isAfter(next))return false;
            if(!c.to().isBefore(to))return true;
            next=c.to().plusDays(1);
        }
        return false;
    }
    static List<ResolutionEvent> latestRelevant(List<ResolutionEvent> events,long instrumentId,Set<UUID> memberJobs,LocalDate from,LocalDate to) {
        var latest=new LinkedHashMap<String,ResolutionEvent>();
        // PostgreSQL UUID DESC uses unsigned lexical order, unlike UUID.compareTo's signed longs.
        var order=Comparator.comparing(ResolutionEvent::createdAt,Comparator.nullsLast(Comparator.reverseOrder()))
                .thenComparing(e->e.id().toString(),Comparator.reverseOrder());
        for(var e:events.stream().sorted(order).toList()) {
            String key=e.jobId()+"|"+e.instrumentId()+"|"+e.findingType()+"|"+e.findingDate()+"|"+e.relatedDate();
            latest.putIfAbsent(key,e);
        }
        return latest.values().stream().filter(e->memberJobs.contains(e.jobId()) && (e.instrumentId()==null || e.instrumentId()==instrumentId)
                && ((!e.findingDate().isBefore(from) && !e.findingDate().isAfter(to)) || overlaps(e.exclusionFrom(),e.exclusionTo(),from,to))).toList();
    }
    public record Job(UUID id,String jobType,String status,LocalDate from,LocalDate to){}
    public record JobLink(Job job,String savedReportReference,boolean completedChunkRangeCoversScope){}
    public record Chunk(UUID jobId,LocalDate from,LocalDate to,String status,int acceptedRows,int rejectedRows){}
    public record Action(long id,String actionType,LocalDate effectiveOn,LocalDate announcedOn,BigDecimal amount,String ratio,Instant receivedAt,String eventFingerprint,boolean hasSourceReference){}
    public record ResolutionEvent(UUID id,UUID jobId,Long instrumentId,String findingType,LocalDate findingDate,LocalDate relatedDate,String eventAction,
            String resolutionType,LocalDate exclusionFrom,LocalDate exclusionTo,Instant createdAt){}
    public record Instrument(long instrumentId,String symbol,boolean partial,List<JobLink> jobLinks,List<Chunk> chunks,List<Action> corporateActions,
            int resolutionEventsInspected,List<ResolutionEvent> latestRelevantResolutions,int overlappingActiveExclusionCount,int revokedFindingCount,List<String> remainingGates){}
    public record Evidence(String version,String status,UUID datasetRunId,String datasetManifestHash,LocalDate fromDate,LocalDate throughDate,int offset,int limit,
            int jobsObserved,boolean jobCatalogTruncated,List<Instrument> instruments,boolean partial,boolean trainingAuthorized,boolean databaseWritesPerformed,
            int modelCallCount,int providerCallCount,int ordersCreated,String limitations){}
}
