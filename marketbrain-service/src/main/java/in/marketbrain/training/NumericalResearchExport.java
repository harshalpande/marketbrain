package in.marketbrain.training;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDate;
import java.util.*;

/** Bounded saved-evidence pilot. No repository, provider, model, or order dependency. */
public final class NumericalResearchExport {
    public static final String VERSION = "NUMERICAL_MULTI_DATE_RESEARCH_V1";
    public static final String CALENDAR_HASH = "ea8cd016a1b03fab1d97b0cdecbdae4ff181b1b22f4a10a21f6ff6f11ca9c086";
    static final LocalDate FIRST = LocalDate.parse("2026-04-10"), LAST = LocalDate.parse("2026-06-05");
    public record Input(UUID datasetRunId, String datasetManifestHash, String featureEvidenceSha256,
                        String outcomeEvidenceSha256, List<LocalDate> sessions, List<Instrument> instruments) { }
    public record Instrument(long instrumentId, String symbol, List<Bar> bars) { }
    public record Bar(long candleId, LocalDate date, String source, Instant receivedAt, BigDecimal open,
                      BigDecimal high, BigDecimal low, BigDecimal close, BigDecimal volume, Boolean excluded) {
        NumericalFeatureSnapshot.SourceBar sourceBar() {
            return new NumericalFeatureSnapshot.SourceBar(candleId,date,source,receivedAt,open,high,low,close,volume,excluded);
        }
        boolean validPrice() {
            return open != null && high != null && low != null && close != null && open.signum()>0 && low.signum()>0
                    && low.compareTo(open)<=0 && low.compareTo(close)<=0 && high.compareTo(open)>=0 && high.compareTo(close)>=0;
        }
    }
    public record CostScenario(int roundTripBps, BigDecimal indicativeNetPercent) { }
    public record Outcome(String status, LocalDate entryDate, LocalDate exitDate, LocalDate problemDate,
                          List<Long> sourceCandleIds, BigDecimal indicativeGrossPercent, List<CostScenario> costSensitivity) { }
    public record Row(long instrumentId, String symbol, LocalDate decisionDate, String featureStatus,
                      NumericalFeatureSnapshot.Row featureSnapshot, Outcome outcome) { }
    public record Result(String version, String status, UUID datasetRunId, String datasetManifestHash,
                         String featureEvidenceSha256, String outcomeEvidenceSha256, String calendarSessionSha256,
                         int decisionDateCount, int candidateRowCount, int completeArithmeticRowCount,
                         int blockedRowCount, List<Row> rows, int certifiedLabelCount, boolean trainingAuthorized,
                         boolean databaseWritesPerformed, int databaseQueryCount, int providerCallCount, int modelCallCount,
                         int ordersCreated, List<String> remainingGates, String limitations) { }

    public Result build(Input input) {
        validate(input);
        var dates=input.sessions().stream().filter(d->!d.isBefore(FIRST)&&!d.isAfter(LAST)).toList();
        var rows=new ArrayList<Row>();
        var calculator=new NumericalFeatureSnapshot();
        for(var instrument:input.instruments()) {
            var source=instrument.bars().stream().map(Bar::sourceBar).toList();
            var byDate=new HashMap<LocalDate,Bar>();instrument.bars().forEach(b->byDate.put(b.date(),b));
            for(var date:dates) {
                // calculate() filters at the decision date BEFORE selecting its 252-bar window.
                var features=calculator.calculate(date,source,false);
                var featureStatus=features.status();
                int index=input.sessions().indexOf(date);
                if(features.features()!=null) {
                    var actual=source.stream().filter(b->features.sourceCandleIds().contains(b.candleId())).map(NumericalFeatureSnapshot.SourceBar::date).toList();
                    featureStatus=index>=251 && actual.equals(input.sessions().subList(index-251,index+1))
                            ? "MATCHES_REVIEWED_CALENDAR" : "FEATURE_CALENDAR_MISMATCH";
                }
                rows.add(new Row(instrument.instrumentId(),instrument.symbol(),date,featureStatus,features,
                        outcome(index,input.sessions(),byDate)));
            }
        }
        int complete=(int)rows.stream().filter(r->r.featureStatus().equals("MATCHES_REVIEWED_CALENDAR")
                &&r.outcome().status().equals("STORED_PRICE_ARITHMETIC_ONLY")).count();
        return new Result(VERSION,"RESEARCH_EXPORT_TRAINING_BLOCKED",input.datasetRunId(),input.datasetManifestHash(),
                input.featureEvidenceSha256(),input.outcomeEvidenceSha256(),CALENDAR_HASH,dates.size(),rows.size(),complete,
                rows.size()-complete,List.copyOf(rows),0,false,false,0,0,0,0,
                List.of("PRICE_ACTION_COVERAGE_AND_ADJUSTMENT_PROVENANCE","EXECUTABLE_PRICE_COST_AND_RESEARCH_POLICY",
                        "BROADER_INDEPENDENT_DATES_AND_FROZEN_PURGED_SPLITS","SOURCE_RIGHTS_MEMBERSHIP_AND_AVAILABILITY_POLICY"),
                "Engineering pilot: four instruments maximum, 38 decision dates, overlapping 20-session outcomes. Dates are not independent samples. "
                +"No folds, fitted model, approved fees, certified labels or performance claims. Retrospective backfill, not as-known replay. "
                +"Saved inputs supplied by caller, not reauthenticated against DB. SHA256 identifies bytes, not truth. "
                +"All blocked rows retained. Price provenance unknown even when arithmetic is complete.");
    }
    private Outcome outcome(int index,List<LocalDate> sessions,Map<LocalDate,Bar> bars) {
        LocalDate entry=sessions.get(index+1),exit=sessions.get(index+20);
        var ids=new ArrayList<Long>();
        for(int i=index+1;i<=index+20;i++) {
            var day=sessions.get(i);var bar=bars.get(day);
            String failure=bar==null?"MISSING_BAR":bar.excluded()?"EXCLUDED_BAR":!bar.validPrice()?"INVALID_OHLC":null;
            if(failure!=null)return new Outcome(failure,entry,exit,day,List.of(),null,List.of());
            ids.add(bar.candleId());
        }
        var gross=bars.get(exit).close().divide(bars.get(entry).open(),16,RoundingMode.HALF_UP)
                .subtract(BigDecimal.ONE).multiply(BigDecimal.valueOf(100)).setScale(8,RoundingMode.HALF_UP);
        var costs=List.of(0,25,50,100).stream().map(bps->new CostScenario(bps,gross.subtract(BigDecimal.valueOf(bps,2)))).toList();
        return new Outcome("STORED_PRICE_ARITHMETIC_ONLY",entry,exit,null,List.copyOf(ids),gross,costs);
    }
    private void validate(Input input) {
        if(input==null||input.datasetRunId()==null||!hash(input.datasetManifestHash())||!hash(input.featureEvidenceSha256())
                ||!hash(input.outcomeEvidenceSha256()))throw new IllegalArgumentException("Explicit evidence identity required.");
        if(input.sessions()==null||input.sessions().size()!=320||input.sessions().contains(null)
                ||!digest(String.join("\n",input.sessions().stream().map(LocalDate::toString).toList())).equals(CALENDAR_HASH))
            throw new IllegalArgumentException("Session sequence is not the reviewed pilot calendar.");
        if(input.instruments()==null||input.instruments().isEmpty()||input.instruments().size()>4)
            throw new IllegalArgumentException("One to four saved instruments required.");
        var instruments=new HashSet<Long>();var symbols=new HashSet<String>();var ids=new HashSet<Long>();
        for(var item:input.instruments()) {
            if(item==null||item.instrumentId()<=0||!instruments.add(item.instrumentId())||item.symbol()==null
                    ||!item.symbol().matches("[A-Z0-9&._-]{1,40}")||!symbols.add(item.symbol())||item.bars()==null||item.bars().size()>700)
                throw new IllegalArgumentException("Invalid instrument identity or bar cap.");
            LocalDate prior=null;
            for(var bar:item.bars()) {
                if(bar==null||bar.candleId()<=0||!ids.add(bar.candleId())||bar.date()==null||bar.excluded()==null
                        ||!("UPSTOX".equals(bar.source())||"NSE_BHAVCOPY".equals(bar.source()))
                        ||prior!=null&&!bar.date().isAfter(prior)||bar.date().isBefore(LocalDate.parse("2024-06-06"))
                        ||bar.date().isAfter(LocalDate.parse("2026-07-17")))throw new IllegalArgumentException("Invalid saved bar identity/order/scope.");
                for(var number:Arrays.asList(bar.open(),bar.high(),bar.low(),bar.close(),bar.volume())) {
                    if(number!=null&&(number.precision()>24||Math.abs((long)number.scale())>12))
                        throw new IllegalArgumentException("Unbounded numeric input.");
                }
                prior=bar.date();
            }
        }
    }
    private boolean hash(String value){return value!=null&&value.matches("[a-fA-F0-9]{64}");}
    public static String digest(String value) {
        try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));}
        catch(java.security.NoSuchAlgorithmException e){throw new IllegalStateException(e);}
    }
}
