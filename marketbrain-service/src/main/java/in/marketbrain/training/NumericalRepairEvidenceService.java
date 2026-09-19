package in.marketbrain.training;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import java.net.URI;
import java.time.LocalDate;
import java.util.*;
import java.util.regex.Pattern;

/** Recover references from already-scoped records. Never approve/apply a price adjustment. */
@Service
public class NumericalRepairEvidenceService {
    private final NumericalPriceEvidenceService prices;
    private final JdbcTemplate jdbc;
    public NumericalRepairEvidenceService(NumericalPriceEvidenceService prices,JdbcTemplate jdbc){this.prices=prices;this.jdbc=jdbc;}
    @Transactional(readOnly=true,timeout=60,isolation=Isolation.REPEATABLE_READ)
    public Evidence inspect(UUID run,LocalDate from,LocalDate through,int offset,int limit){
        var context=prices.inspectThrough(run,from,through,offset,limit);
        var resolutionIds=context.instruments().stream().flatMap(i->i.latestRelevantResolutions().stream()).map(NumericalPriceEvidenceService.ResolutionEvent::id).distinct().sorted().toList();
        var actionIds=context.instruments().stream().flatMap(i->i.corporateActions().stream()).map(NumericalPriceEvidenceService.Action::id).distinct().sorted().toList();
        var references=new ArrayList<Reference>();
        var selectedResolutions=resolutionIds.stream().limit(200).toList();
        var selectedActions=actionIds.stream().limit(200).toList();
        if(!selectedResolutions.isEmpty()){
            String slots=String.join(",",Collections.nCopies(selectedResolutions.size(),"?"));
            references.addAll(jdbc.query("SELECT id, evidence_source, evidence_url, notes FROM market_data_quality_resolution_event WHERE id IN ("+slots+") ORDER BY id",
                    s->{for(int i=0;i<selectedResolutions.size();i++)s.setObject(i+1,selectedResolutions.get(i));s.setQueryTimeout(3);},
                    (r,n)->reference("RESOLUTION",r.getObject("id",UUID.class).toString(),r.getString("evidence_source"),r.getString("evidence_url"),r.getString("notes"))));
        }
        if(!selectedActions.isEmpty()){
            String slots=String.join(",",Collections.nCopies(selectedActions.size(),"?"));
            references.addAll(jdbc.query("SELECT id, source_url FROM corporate_action_event WHERE id IN ("+slots+") ORDER BY id",
                    s->{for(int i=0;i<selectedActions.size();i++)s.setLong(i+1,selectedActions.get(i));s.setQueryTimeout(3);},
                    (r,n)->reference("CORPORATE_ACTION",Long.toString(r.getLong("id")),null,r.getString("source_url"),null)));
        }
        boolean incomplete=references.size()!=selectedActions.size()+selectedResolutions.size();
        boolean partial=context.partial()||resolutionIds.size()>200||actionIds.size()>200||incomplete;
        return new Evidence("NUMERICAL_REPAIR_EVIDENCE_V1","REPAIR_PROVENANCE_REVIEW_REQUIRED",context,List.copyOf(references),resolutionIds.size(),actionIds.size(),partial,
                false,false,0,0,0,"Latest scoped resolution/revocation identities are inherited from price evidence. At most 200 references of each type. "
                +"No raw notes, reviewer identities or arbitrary source text/URLs shared; originals remain in DB and hashes identify them. "
                +"Numeric hints are unverified recorded claims, not applied factors. Empty/capped evidence does not prove no repairs/actions. "
                +"Current state only; adjustments after the requested period and older/out-of-catalog jobs may be relevant but are not certified. No provider fetch, price rewrite or training.");
    }
    static Reference reference(String kind,String id,String source,String rawUrl,String notes){
        String safe=null;
        try {
            var uri=URI.create(rawUrl==null?"":rawUrl);
            // Narrow public exchange archive paths only; query, fragment, user-info, port and escapes rejected.
            if("https".equals(uri.getScheme())&&"nsearchives.nseindia.com".equals(uri.getHost())&&uri.getUserInfo()==null
                    &&uri.getPort()==-1&&uri.getQuery()==null&&uri.getFragment()==null&&rawUrl.length()<=500
                    &&uri.getRawPath().matches("/(?:content/circulars|corporate|content/historical)/[A-Za-z0-9_./-]+\\.(?:pdf|csv|zip)")
                    &&!uri.getRawPath().contains(".."))safe=uri.toASCIIString();
        }catch(IllegalArgumentException ignored){ /* Untrusted reference remains hashed, never fetched. */ }
        var hints=new ArrayList<FactorHint>();
        if(notes!=null){
            var matcher=Pattern.compile("(?:^|[,;\\s])(priceDivisor|volumeMultiplier|reviewedAdjustment|reviewedBonus)\\s*=\\s*([0-9]{1,6}(?:\\.[0-9]{1,6})?(?::[0-9]{1,6})?)(?=$|[,;\\s])").matcher(notes);
            while(matcher.find()&&hints.size()<8)hints.add(new FactorHint(matcher.group(1),matcher.group(2)));
        }
        return new Reference(kind,id,hash(source),safe,hash(rawUrl),notes!=null&&!notes.isBlank(),hash(notes),List.copyOf(hints),
                safe!=null?"PUBLIC_ARCHIVE_REFERENCE_NOT_FETCHED":"REFERENCE_ABSENT_OR_WITHHELD");
    }
    private static String hash(String s){return s==null||s.isBlank()?null:NumericalResearchExport.digest(s);}
    public record FactorHint(String field,String recordedValue){}
    public record Reference(String kind,String recordId,String evidenceSourceSha256,String publicReference,String originalReferenceSha256,
                            boolean notesPresent,String notesSha256,List<FactorHint> unverifiedFactorHints,String referenceStatus){}
    public record Evidence(String version,String status,NumericalPriceEvidenceService.Evidence priceEvidence,List<Reference> references,
                           int scopedResolutionCount,int scopedActionCount,boolean partial,boolean trainingAuthorized,boolean databaseWritesPerformed,
                           int providerCallCount,int modelCallCount,int ordersCreated,String limitations){}
}
