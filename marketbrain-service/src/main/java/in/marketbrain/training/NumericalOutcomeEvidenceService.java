package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

/** Bounded read of missing outcome bars only; future bars never enter the feature calculator. */
@Service
public class NumericalOutcomeEvidenceService {
    static final String RUN_SQL="""
            SELECT as_of, label_through, dataset_manifest_hash, instrument_count
            FROM prototype_swing_training_dataset_run WHERE id = ? AND status = 'COMPLETED'
            """;
    static final String BARS_SQL=NumericalFeatureSnapshotService.BARS_SQL.replace("LIMIT 2001","LIMIT 201");
    private final JdbcTemplate jdbc;
    private final NumericalPriceEvidenceService prices;
    public NumericalOutcomeEvidenceService(JdbcTemplate jdbc,NumericalPriceEvidenceService prices){this.jdbc=jdbc;this.prices=prices;}
    record Run(LocalDate asOf,LocalDate labelThrough,String manifest,int count){}

    @Transactional(readOnly=true,timeout=60,isolation=Isolation.REPEATABLE_READ)
    public Evidence inspect(UUID runId,LocalDate featureFrom,LocalDate through,int offset,int limit){
        if(runId==null || runId.equals(new UUID(0,0)) || featureFrom==null || through==null || offset<0 || offset>499 || limit<1 || limit>4)
            throw new IllegalArgumentException("Explicit run/date bounds required; offset 0..499, limit 1..4.");
        var runs=jdbc.query(RUN_SQL,s->{s.setObject(1,runId);s.setQueryTimeout(3);},(r,n)->new Run(
                r.getObject("as_of",LocalDate.class),r.getObject("label_through",LocalDate.class),r.getString("dataset_manifest_hash"),r.getInt("instrument_count")));
        if(runs.size()!=1)throw new IllegalArgumentException("Completed run not found.");
        var run=runs.getFirst();
        if(run.asOf()==null || run.labelThrough()==null || run.manifest()==null || !run.manifest().matches("[a-fA-F0-9]{64}") || run.count()<1 || run.count()>500 || offset>=run.count())
            throw new IllegalStateException("Invalid run metadata.");
        if(!through.isAfter(run.asOf()) || through.isAfter(run.asOf().plusDays(45)) || through.isAfter(run.labelThrough()) ||
                featureFrom.isAfter(run.asOf()) || featureFrom.isBefore(run.asOf().minusDays(729)))
            throw new IllegalArgumentException("Outcome through must be after as-of, within 45 days and stored label-through; feature start within 730 days.");
        var items=jdbc.query(NumericalFeatureSnapshotService.ITEMS_SQL,s->{s.setObject(1,runId);s.setInt(2,limit);s.setInt(3,offset);s.setQueryTimeout(3);},
                (r,n)->new NumericalFeatureSnapshotService.Item(r.getLong("instrument_id"),r.getString("symbol")));
        if(items.size()!=Math.min(limit,run.count()-offset) || items.stream().map(NumericalFeatureSnapshotService.Item::id).distinct().count()!=items.size())
            throw new IllegalStateException("Instrument scope mismatch.");
        var from=run.asOf().plusDays(1);var results=new ArrayList<Instrument>();
        for(var item:items){
            var bars=jdbc.query(BARS_SQL,s->{
                s.setLong(1,item.id());s.setObject(2,through);s.setObject(3,from);s.setLong(4,item.id());
                s.setTimestamp(5,Timestamp.from(from.atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
                s.setTimestamp(6,Timestamp.from(through.plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
                s.setFetchSize(201);s.setQueryTimeout(5);
            },(r,n)->{
                var received=r.getTimestamp("received_at");
                return new NumericalFeatureSnapshot.SourceBar(r.getLong("id"),r.getObject("trading_date",LocalDate.class),r.getString("source_code"),
                        received==null?null:received.toInstant(),r.getBigDecimal("open_price"),r.getBigDecimal("high_price"),r.getBigDecimal("low_price"),r.getBigDecimal("close_price"),r.getBigDecimal("volume"),r.getBoolean("excluded"));
            });
            results.add(new Instrument(item.id(),item.symbol(),bars.size(),bars.size()>200,new NumericalFeatureSnapshot().canonicalize(bars)));
        }
        // Same repeatable-read transaction; current policy view, not as-known historical evidence.
        var priceEvidence=prices.inspectThrough(runId,featureFrom,through,offset,limit);
        if(!run.manifest().equals(priceEvidence.datasetManifestHash()) || priceEvidence.instruments().size()!=items.size())throw new IllegalStateException("Price scope drift.");
        for(int i=0;i<items.size();i++)if(items.get(i).id()!=priceEvidence.instruments().get(i).instrumentId() || !items.get(i).symbol().equals(priceEvidence.instruments().get(i).symbol()))throw new IllegalStateException("Price identity drift.");
        return new Evidence("NUMERICAL_OUTCOME_EVIDENCE_V1","OUTCOME_EVIDENCE_REVIEW_REQUIRED",runId,run.manifest(),run.asOf(),from,through,offset,limit,List.copyOf(results),priceEvidence,
                priceEvidence.partial() || results.stream().anyMatch(Instrument::truncated),false,false,0,0,0,
                "New bars are outcome-only; no feature recalculation. Current-source canonicalization and exclusion view, not historical vintage. "
                        +"No action coverage or adjustment-factor certification. Stored OHLC is not verified executable price. No actual labels, fitting or provider calls.");
    }
    public record Instrument(long instrumentId,String symbol,int rawRowCount,boolean truncated,List<NumericalFeatureSnapshot.SourceBar> canonicalBars){}
    public record Evidence(String version,String status,UUID datasetRunId,String datasetManifestHash,LocalDate asOf,LocalDate outcomeFrom,LocalDate outcomeThrough,int offset,int limit,
            List<Instrument> instruments,NumericalPriceEvidenceService.Evidence priceEvidence,boolean partial,boolean trainingAuthorized,boolean databaseWritesPerformed,int modelCallCount,int providerCallCount,int ordersCreated,String limitations){}
}
