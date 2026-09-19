package in.marketbrain.training;

import java.io.*;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** Isolated JDK-only engineering lab. No bean, endpoint, database, network, or market-data loader.
 * The ONLY executable entry point generates fixed synthetic fixtures. Not a market-fit release. */
public final class NumericalTenFeatureEngineering {
    public static final String VERSION = "NUMERICAL_TEN_FEATURE_ENGINEERING_V1";
    static final String POLICY = "SYNTHETIC_20_SESSION_PRICE_RETURN_V1";
    static final String CONTRACT = "NUMERICAL_TEN_FEATURE_PREFIT_V1";
    static final String CONTRACT_SHA = "0ca5efab05b6fde03c16adb4181e31d63893e80fee8b71a63087eb35385a69d6";
    static final double ALPHA = 0.01, TOLERANCE = 1e-9;
    static final int MAX_ROWS = 10_000;
    static final List<String> FEATURES = List.of("dailyReturnPercent", "closeToSma20Percent",
            "closeToSma50Percent", "closeToSma200Percent", "ema12ToEma26Percent", "rsi14",
            "atr14ToClosePercent", "annualizedVolatility20Percent", "volumeRatio20", "rangePosition252Percent");
    static final List<String> UNITS = List.of("PERCENT", "PERCENT", "PERCENT", "PERCENT", "PERCENT",
            "INDEX_0_100", "PERCENT", "PERCENT", "RATIO", "PERCENT_0_100");
    enum Partition { TRAIN, VALIDATION, TEST }
    record Input(String instrument, Instant decisionAt, Instant availableAt, Map<String, Double> features) {
        Input { if (features != null) features = Collections.unmodifiableMap(new LinkedHashMap<>(features)); }
    }
    record Row(Input input, Double target, Instant labelEnd, Instant labelAvailable, Partition partition,
               boolean inspected, String evidencePolicy) { }
    record Window(LocalDate first, LocalDate last) { }
    record Manifest(List<LocalDate> sessions, Map<Partition, Window> windows, List<Window> inspected,
                    boolean sealedFinal, int gapSessions) {
        Manifest { sessions=List.copyOf(sessions); windows=Map.copyOf(windows); inspected=List.copyOf(inspected); }
    }
    record Exclusion(String instrument, Instant decisionAt, Partition partition, String reason) { }
    record Prepared(List<Row> eligible, List<Exclusion> excluded, int inputRows) { }
    record Model(String version, List<String> featureOrder, List<String> featureUnits, List<Double> means,
                 List<Double> scales, List<Boolean> constants, List<Double> coefficients, double intercept,
                 double trainingMean, double alpha, Map<String,String> metadata) {
        Model {
            featureOrder=List.copyOf(featureOrder); featureUnits=List.copyOf(featureUnits);
            means=List.copyOf(means); scales=List.copyOf(scales); constants=List.copyOf(constants);
            coefficients=List.copyOf(coefficients); metadata=Map.copyOf(metadata);
        }
    }
    record Prediction(String instrument, Instant decisionAt, double observed, double predicted) { }
    record Metrics(int rows, int dates, double mae, double rmse, double signedBias,
                   double directionAgreementPercent, Double meanWithinDateRankCorrelation, int rankDates) { }
    record Cost(int roundTripBps, int selectedCount, Double meanSelectedNetPercent) { }
    record Comparison(String predictor, List<Prediction> predictions, Metrics metrics,
                      Double maeImprovementVsZeroPercent, List<Cost> hypotheticalCosts) { }
    record Evaluation(int inputRows, int evaluatedRows, double coveragePercent, List<Exclusion> exclusions,
                      List<Comparison> comparisons) { }
    record Fold(String name, String fixtureHash, Manifest manifest, Model model, String artifact,
                String artifactHash, int inputRows, List<Exclusion> exclusions, Evaluation validation,
                Evaluation test, double elapsedMillis) { }
    record Check(String name, boolean passed, double elapsedMillis, String failure) { }
    record Uncertainty(String scope, int dates, int blockLength, int resamples, long seed,
                       double confidenceLevel, double meanErrorReduction, double lower, double upper,
                       String sampleMeansHash) { }
    static void require(boolean ok, String message) { if(!ok) throw new IllegalArgumentException(message); }
    static double finite(double n) { require(Double.isFinite(n), "NON_FINITE_OR_OVERFLOW"); return n; }
    static LocalDate date(Instant at) { return at.atZone(ZoneId.of("Asia/Kolkata")).toLocalDate(); }
    static Instant instant(LocalDate d) { return d.atTime(16,0).atZone(ZoneId.of("Asia/Kolkata")).toInstant(); }
    static void bounded(String s) { require(s!=null && !s.isBlank() && s.length()<=200, "INVALID_IDENTIFIER"); }
    static String inputIssue(Input i) {
        if(i==null || i.instrument()==null || i.instrument().isBlank() || i.instrument().length()>100 || i.decisionAt()==null) return "INVALID_IDENTITY";
        if(i.availableAt()==null) return "UNKNOWN_AVAILABILITY";
        if(i.availableAt().isAfter(i.decisionAt())) return "FUTURE_AVAILABILITY";
        if(i.features()==null || !i.features().keySet().equals(new HashSet<>(FEATURES))) return "FEATURE_SCHEMA_MISMATCH";
        for(var name:FEATURES) if(i.features().get(name)==null || !Double.isFinite(i.features().get(name))) return "MISSING_OR_NON_FINITE_FEATURE";
        return null;
    }
    static void validateManifest(Manifest m) {
        require(m!=null && m.sessions().size()<=MAX_ROWS && !m.sessions().isEmpty(), "INVALID_MANIFEST");
        for(int i=1;i<m.sessions().size();i++) require(m.sessions().get(i).isAfter(m.sessions().get(i-1)), "UNORDERED_CALENDAR");
        require(m.windows().keySet().equals(Set.of(Partition.values())) && m.gapSessions()>=20, "INVALID_PARTITIONS_OR_GAP");
        int last=-1;
        for(var p:Partition.values()) {
            var w=m.windows().get(p); int a=m.sessions().indexOf(w.first()), b=m.sessions().indexOf(w.last());
            require(a>=0 && b>=a && (last<0 || a-last-1>=m.gapSessions()), "PARTITION_OVERLAP_OR_INSUFFICIENT_GAP"); last=b;
        }
        for(var w:m.inspected()) require(w!=null && w.first()!=null && w.last()!=null && !w.last().isBefore(w.first()), "INVALID_INSPECTION_WINDOW");
        if(m.sealedFinal()) {
            var test=m.windows().get(Partition.TEST);
            for(var w:m.inspected()) require(w.last().isBefore(test.first()) || w.first().isAfter(test.last()), "INSPECTED_FINAL_TEST");
        }
    }
    /** Exclusions retain their denominator; malformed identity/duplicates/partition escapes fail the whole fold. */
    static Prepared prepare(Manifest m, List<Row> rows) {
        validateManifest(m); require(rows!=null && !rows.isEmpty() && rows.size()<=MAX_ROWS,"INVALID_ROWS");
        var accepted=new ArrayList<Row>(); var excluded=new ArrayList<Exclusion>(); var keys=new HashSet<String>();
        for(var r:rows) {
            require(r!=null && r.input()!=null && r.input().decisionAt()!=null && r.partition()!=null,"INVALID_ROW");
            bounded(r.input().instrument()); var i=r.input(); var d=date(i.decisionAt()); var w=m.windows().get(r.partition());
            require(!d.isBefore(w.first()) && !d.isAfter(w.last()) && m.sessions().contains(d),"ROW_OUTSIDE_PARTITION");
            require(keys.add(i.instrument()+"@"+i.decisionAt()),"DUPLICATE_IDENTITY");
            String issue=inputIssue(i);
            if(issue==null && !POLICY.equals(r.evidencePolicy())) issue="UNCERTIFIED_OR_MARKET_DATA_DISABLED";
            if(issue==null && (r.target()==null || !Double.isFinite(r.target()))) issue="MISSING_OR_NON_FINITE_TARGET";
            if(issue==null && (r.labelEnd()==null || r.labelAvailable()==null)) issue="UNKNOWN_LABEL_AVAILABILITY";
            int end=m.sessions().indexOf(d)+20;
            if(issue==null && (end>=m.sessions().size() || !r.labelEnd().equals(instant(m.sessions().get(end))) || r.labelAvailable().isBefore(r.labelEnd()))) issue="LABEL_POLICY_MISMATCH";
            if(issue==null && r.partition()!=Partition.TEST) {
                var next=r.partition()==Partition.TRAIN?Partition.VALIDATION:Partition.TEST;
                var boundary=instant(m.windows().get(next).first());
                if(!r.labelEnd().isBefore(boundary) || !r.labelAvailable().isBefore(boundary)) issue="PURGED_LABEL_OVERLAP";
            }
            if(m.sealedFinal() && r.partition()==Partition.TEST) require(!r.inspected(),"INSPECTED_FINAL_TEST");
            if(issue==null) accepted.add(r); else excluded.add(new Exclusion(i.instrument(),i.decisionAt(),r.partition(),issue));
        }
        accepted.sort(Comparator.comparing((Row r)->r.input().decisionAt()).thenComparing(r->r.input().instrument()));
        excluded.sort(Comparator.comparing(Exclusion::decisionAt).thenComparing(Exclusion::instrument));
        for(var p:Partition.values()) require(accepted.stream().anyMatch(r->r.partition()==p),"EMPTY_ELIGIBLE_"+p);
        return new Prepared(List.copyOf(accepted),List.copyOf(excluded),rows.size());
    }
    static double[] weights(List<Row> rows) {
        var counts=new TreeMap<LocalDate,Integer>(); for(var r:rows) counts.merge(date(r.input().decisionAt()),1,Integer::sum);
        double[] w=new double[rows.size()]; for(int i=0;i<w.length;i++) w[i]=1.0/(counts.size()*counts.get(date(rows.get(i).input().decisionAt())));
        return w;
    }
    static List<Double> boxed(double[] values) { return Arrays.stream(values).boxed().toList(); }
    static double[] vector(Input i) {
        require(inputIssue(i)==null,"INVALID_PREDICTION_INPUT: "+inputIssue(i));
        return FEATURES.stream().mapToDouble(f->i.features().get(f)).toArray();
    }
    static Model fit(Manifest m, List<Row> input, String codeRevision) {
        bounded(codeRevision); var p=prepare(m,input);
        var rows=p.eligible().stream().filter(r->r.partition()==Partition.TRAIN).toList();
        require(rows.size()>=2,"INSUFFICIENT_TRAINING"); double[] w=weights(rows),mean=new double[10],scale=new double[10]; double y=0;
        double[] anchor=vector(rows.getFirst().input()); double targetAnchor=rows.getFirst().target();
        for(int i=0;i<rows.size();i++) {
            double[] x=vector(rows.get(i).input()); y=finite(y+finite(w[i]*finite(rows.get(i).target()-targetAnchor)));
            for(int j=0;j<10;j++) mean[j]=finite(mean[j]+finite(w[i]*finite(x[j]-anchor[j])));
        }
        y=finite(y+targetAnchor); for(int j=0;j<10;j++)mean[j]=finite(mean[j]+anchor[j]);
        for(int i=0;i<rows.size();i++) { double[] x=vector(rows.get(i).input()); for(int j=0;j<10;j++) {
            double delta=finite(x[j]-mean[j]); scale[j]=finite(scale[j]+finite(w[i]*finite(delta*delta)));
        }}
        var constants=new ArrayList<Boolean>(); for(int j=0;j<10;j++) {constants.add(scale[j]==0);scale[j]=scale[j]==0?1:Math.sqrt(scale[j]);}
        double[][] a=new double[10][10]; double[] b=new double[10];
        for(int i=0;i<rows.size();i++) {
            double[] x=vector(rows.get(i).input()); for(int j=0;j<10;j++) x[j]=finite((x[j]-mean[j])/scale[j]);
            for(int j=0;j<10;j++) {
                b[j]=finite(b[j]+finite(w[i]*x[j]*finite(rows.get(i).target()-y)));
                for(int k=0;k<10;k++) a[j][k]=finite(a[j][k]+finite(w[i]*x[j]*x[k]));
            }
        }
        for(int j=0;j<10;j++) a[j][j]=finite(a[j][j]+ALPHA);
        double[] coefficients=solve(a,b);
        var metadata=new TreeMap<String,String>();
        metadata.put("contractVersion",CONTRACT); metadata.put("contractHash",CONTRACT_SHA);
        metadata.put("codeRevision",codeRevision); metadata.put("labelPolicyHash",sha(POLICY));
        metadata.put("objectiveNormalization","SUM_DATE_WEIGHTS_ONE_INTERCEPT_UNPENALIZED");
        metadata.put("fitCutoff",instant(m.windows().get(Partition.VALIDATION).first()).toString());
        metadata.put("trainingSourceHash",sha(json(rows))); metadata.put("eligibilityEvidenceHash",sha(json(rows.stream().map(r->List.of(r.input().instrument(),r.input().availableAt(),r.evidencePolicy())).toList())));
        metadata.put("foldManifestHash",sha(json(m))); metadata.put("inspectionLedgerHash",sha(json(m.inspected())));
        metadata.put("trainingRowCount",Integer.toString(rows.size())); metadata.put("trainingDateCount",Long.toString(rows.stream().map(r->date(r.input().decisionAt())).distinct().count()));
        metadata.put("runtimeVersion",System.getProperty("java.version")); metadata.put("dataScope","SYNTHETIC_ONLY");
        var model=new Model(VERSION,FEATURES,UNITS,boxed(mean),boxed(scale),constants,boxed(coefficients),y,y,ALPHA,metadata);
        validateModel(model); return model;
    }
    /** Cholesky on a fixed 10x10 SPD system, with independent residual check; never retries by changing alpha. */
    static double[] solve(double[][] a,double[] b) {
        double[][] l=new double[10][10]; double[] z=new double[10],x=new double[10];
        for(int j=0;j<10;j++) for(int k=0;k<=j;k++) {
            double s=a[j][k]; for(int t=0;t<k;t++) s=finite(s-l[j][t]*l[k][t]);
            if(j==k) {require(s>1e-14,"UNSTABLE_SOLVE");l[j][k]=Math.sqrt(s);} else l[j][k]=finite(s/l[k][k]);
        }
        for(int j=0;j<10;j++) {double s=b[j];for(int k=0;k<j;k++)s=finite(s-l[j][k]*z[k]);z[j]=finite(s/l[j][j]);}
        for(int j=9;j>=0;j--) {double s=z[j];for(int k=j+1;k<10;k++)s=finite(s-l[k][j]*x[k]);x[j]=finite(s/l[j][j]);}
        for(int j=0;j<10;j++) {double residual=-b[j],magnitude=Math.abs(b[j]);for(int k=0;k<10;k++){residual=finite(residual+a[j][k]*x[k]);magnitude=finite(magnitude+Math.abs(a[j][k]*x[k]));}
            require(Math.abs(residual)<=TOLERANCE*Math.max(1,magnitude),"SOLVE_RESIDUAL_FAILURE");}
        return x;
    }
    static void validateModel(Model m) {
        require(m!=null && VERSION.equals(m.version()) && FEATURES.equals(m.featureOrder()) && UNITS.equals(m.featureUnits()),"ARTIFACT_SCHEMA_MISMATCH");
        require(m.means().size()==10 && m.scales().size()==10 && m.coefficients().size()==10 && m.constants().size()==10,"ARTIFACT_DIMENSION");
        finite(m.intercept());finite(m.trainingMean());require(m.alpha()==ALPHA && m.intercept()==m.trainingMean(),"ARTIFACT_OBJECTIVE");
        for(int j=0;j<10;j++){finite(m.means().get(j));finite(m.coefficients().get(j));require(finite(m.scales().get(j))>0,"ARTIFACT_SCALE");if(m.constants().get(j))require(m.scales().get(j)==1 && m.coefficients().get(j)==0,"ARTIFACT_CONSTANT");}
        require(m.metadata().keySet().equals(Set.of("contractVersion","contractHash","codeRevision","labelPolicyHash","objectiveNormalization","fitCutoff","trainingSourceHash","eligibilityEvidenceHash","foldManifestHash","inspectionLedgerHash","trainingRowCount","trainingDateCount","runtimeVersion","dataScope")),"ARTIFACT_METADATA");
        m.metadata().values().forEach(NumericalTenFeatureEngineering::bounded);
        for(var key:List.of("contractHash","labelPolicyHash","trainingSourceHash","eligibilityEvidenceHash","foldManifestHash","inspectionLedgerHash"))require(m.metadata().get(key).matches("[a-f0-9]{64}"),"ARTIFACT_HASH");
        require(CONTRACT.equals(m.metadata().get("contractVersion")) && "SYNTHETIC_ONLY".equals(m.metadata().get("dataScope")) && sha(POLICY).equals(m.metadata().get("labelPolicyHash")),"ARTIFACT_POLICY");
        require(m.metadata().get("contractHash").equals(CONTRACT_SHA) && "SUM_DATE_WEIGHTS_ONE_INTERCEPT_UNPENALIZED".equals(m.metadata().get("objectiveNormalization")),"ARTIFACT_CONTRACT");
        int n=Integer.parseInt(m.metadata().get("trainingRowCount")),d=Integer.parseInt(m.metadata().get("trainingDateCount"));
        require(n>=2 && n<=MAX_ROWS && d>0 && d<=n,"ARTIFACT_COUNTS");Instant.parse(m.metadata().get("fitCutoff"));
    }
    static double predict(Model m,Input i) {
        validateModel(m);double[] x=vector(i);double value=m.intercept();
        require(!i.decisionAt().isBefore(Instant.parse(m.metadata().get("fitCutoff"))),"PREDICTION_BEFORE_FIT_CUTOFF");
        for(int j=0;j<10;j++)value=finite(value+finite((x[j]-m.means().get(j))/m.scales().get(j))*m.coefficients().get(j));return value;
    }
    /** Portable bounded binary payload with SHA256. Checksum detects corruption, not malicious signing. */
    static String encode(Model m) {
        validateModel(m);try {
            var bytes=new ByteArrayOutputStream();var out=new DataOutputStream(bytes);out.writeUTF(m.version());
            for(var names:List.of(m.featureOrder(),m.featureUnits()))for(var s:names)out.writeUTF(s);
            for(var values:List.of(m.means(),m.scales(),m.coefficients()))for(var v:values)out.writeDouble(v);
            for(boolean c:m.constants())out.writeBoolean(c);out.writeDouble(m.intercept());out.writeDouble(m.trainingMean());out.writeDouble(m.alpha());
            out.writeInt(m.metadata().size());for(var e:new TreeMap<>(m.metadata()).entrySet()){out.writeUTF(e.getKey());out.writeUTF(e.getValue());}out.flush();
            String payload=Base64.getEncoder().encodeToString(bytes.toByteArray());return sha(payload)+":"+payload;
        }catch(IOException e){throw new IllegalStateException(e);}
    }
    static Model decode(String artifact,Map<String,String> expectedIdentity) {
        require(artifact!=null && artifact.length()<20_000 && artifact.indexOf(':')==64,"INVALID_ARTIFACT_ENVELOPE");
        String payload=artifact.substring(65);require(sha(payload).equals(artifact.substring(0,64)),"ARTIFACT_CHECKSUM");
        try {
            var in=new DataInputStream(new ByteArrayInputStream(Base64.getDecoder().decode(payload)));String version=in.readUTF();
            var names=new ArrayList<String>();var units=new ArrayList<String>();for(int i=0;i<10;i++)names.add(in.readUTF());for(int i=0;i<10;i++)units.add(in.readUTF());
            var means=new ArrayList<Double>();var scales=new ArrayList<Double>();var coefficients=new ArrayList<Double>();
            for(var list:List.of(means,scales,coefficients))for(int i=0;i<10;i++)list.add(in.readDouble());
            var constants=new ArrayList<Boolean>();for(int i=0;i<10;i++)constants.add(in.readBoolean());
            double intercept=in.readDouble(),mean=in.readDouble(),alpha=in.readDouble();require(in.readInt()==14,"ARTIFACT_METADATA_SIZE");
            var metadata=new TreeMap<String,String>();for(int i=0;i<14;i++)require(metadata.put(in.readUTF(),in.readUTF())==null,"DUPLICATE_METADATA");require(in.read()==-1,"TRAILING_ARTIFACT_DATA");
            var m=new Model(version,names,units,means,scales,constants,coefficients,intercept,mean,alpha,metadata);validateModel(m);
            require(expectedIdentity!=null && metadata.equals(expectedIdentity),"ARTIFACT_IDENTITY_MISMATCH");return m;
        }catch(IOException e){throw new IllegalArgumentException("INVALID_ARTIFACT",e);}
    }
    static double[] ranks(double[] values) {
        double[] result=new double[values.length];for(int i=0;i<values.length;i++){int lower=0,equal=0;for(double v:values){if(v<values[i])lower++;if(v==values[i])equal++;}result[i]=lower+(equal+1)/2.0;}return result;
    }
    static Double correlation(List<Prediction> rows) {
        if(rows.size()<2)return null;double[] x=ranks(rows.stream().mapToDouble(Prediction::predicted).toArray()),y=ranks(rows.stream().mapToDouble(Prediction::observed).toArray());
        double mean=(rows.size()+1)/2.0,a=0,b=0,c=0;for(int i=0;i<x.length;i++){a+=(x[i]-mean)*(y[i]-mean);b+=Math.pow(x[i]-mean,2);c+=Math.pow(y[i]-mean,2);}return b==0 || c==0?null:finite(a/Math.sqrt(b*c));
    }
    static Metrics metrics(List<Prediction> rows) {
        require(!rows.isEmpty() && rows.size()<=MAX_ROWS,"EMPTY_OR_OVERSIZED_METRICS");var groups=new TreeMap<LocalDate,List<Prediction>>();
        for(var r:rows){finite(r.predicted());finite(r.observed());groups.computeIfAbsent(date(r.decisionAt()),ignored->new ArrayList<>()).add(r);}
        double a=0,q=0,s=0,correct=0,rank=0;int rankDates=0;
        for(var group:groups.values()) {
            for(var r:group){double e=finite(r.predicted()-r.observed()),w=1.0/(groups.size()*group.size());a=finite(a+w*Math.abs(e));q=finite(q+w*finite(e*e));s=finite(s+w*e);correct+=w*(Math.signum(r.predicted())==Math.signum(r.observed())?1:0);}
            Double corr=correlation(group);if(corr!=null){rank+=corr;rankDates++;}
        }
        return new Metrics(rows.size(),groups.size(),a,Math.sqrt(q),s,100*correct,rankDates==0?null:rank/rankDates,rankDates);
    }
    static Double improvement(double baseline,double candidate) { return baseline==0?null:finite(100*(baseline-candidate)/baseline); }
    /** Paired moving blocks of DATE means, not independently bootstrapped stock rows.
     * This is numerical machinery only; market block length/coverage/confidence remain unapproved. */
    static Uncertainty uncertainty(List<Prediction> baseline,List<Prediction> candidate,int block,int samples,long seed,double confidence) {
        require(baseline!=null && candidate!=null && baseline.size()==candidate.size() && !baseline.isEmpty() && baseline.size()<=MAX_ROWS,"UNPAIRED_UNCERTAINTY");
        require(samples>=20 && samples<=2000 && confidence>0 && confidence<1,"INVALID_RESAMPLING_PARAMETERS");
        var reference=new TreeMap<String,Prediction>();for(var p:baseline)require(reference.put(p.instrument()+"@"+p.decisionAt(),p)==null,"DUPLICATE_UNCERTAINTY_ROW");
        var groups=new TreeMap<LocalDate,List<Double>>();var seen=new HashSet<String>();
        for(var c:candidate.stream().sorted(Comparator.comparing(Prediction::decisionAt).thenComparing(Prediction::instrument)).toList()){String key=c.instrument()+"@"+c.decisionAt();var b=reference.get(key);require(b!=null && seen.add(key) && b.observed()==c.observed(),"UNPAIRED_UNCERTAINTY");
            double difference=finite(Math.abs(finite(b.predicted()-b.observed()))-Math.abs(finite(c.predicted()-c.observed())));groups.computeIfAbsent(date(c.decisionAt()),ignored->new ArrayList<>()).add(difference);}
        int n=groups.size();require(n<=1000 && block>=1 && block<=n/2,"INSUFFICIENT_DATES_OR_INVALID_BLOCK");
        double[] values=new double[n];int at=0;for(var g:groups.values()){double sum=0;for(double v:g)sum=finite(sum+v/g.size());values[at++]=sum;}
        double mean=0;for(double v:values)mean=finite(mean+v/n);
        var random=new Random(seed);double[] draws=new double[samples];
        for(int r=0;r<samples;r++){int count=0;double sum=0;while(count<n){int start=random.nextInt(n-block+1);for(int j=0;j<block && count<n;j++,count++)sum=finite(sum+values[start+j]/n);}draws[r]=sum;}
        String hash=sha(json(boxed(draws)));Arrays.sort(draws);double tail=(1-confidence)/2;
        int lower=Math.max(0,(int)Math.ceil(tail*samples)-1),upper=Math.min(samples-1,(int)Math.ceil((1-tail)*samples)-1);
        return new Uncertainty("SYNTHETIC_PARAMETERS_NOT_MARKET_ACCEPTANCE",n,block,samples,seed,confidence,mean,draws[lower],draws[upper],hash);
    }
    static Evaluation evaluate(Model model,Prepared p,Partition partition) {
        require(partition!=Partition.TRAIN,"TRAIN_NOT_EVALUATION");var rows=p.eligible().stream().filter(r->r.partition()==partition).toList();
        var excluded=new ArrayList<>(p.excluded().stream().filter(e->e.partition()==partition).toList());
        var common=new ArrayList<Row>();var values=new ArrayList<Double>();
        for(var r:rows)try{double v=predict(model,r.input());common.add(r);values.add(v);}catch(IllegalArgumentException e){excluded.add(new Exclusion(r.input().instrument(),r.input().decisionAt(),partition,"PREDICTION_FAILURE: "+e.getMessage()));}
        int inputRows=rows.size()+(int)p.excluded().stream().filter(e->e.partition()==partition).count();var comparisons=new ArrayList<Comparison>();
        double zero=0;
        for(var predictor:List.of("ZERO_RETURN","WEIGHTED_TRAIN_MEAN","TEN_FEATURE_WEIGHTED_RIDGE")) {
            var predictions=new ArrayList<Prediction>();for(int i=0;i<common.size();i++){var r=common.get(i);double v=predictor.equals("ZERO_RETURN")?0:predictor.equals("WEIGHTED_TRAIN_MEAN")?model.trainingMean():values.get(i);predictions.add(new Prediction(r.input().instrument(),r.input().decisionAt(),r.target(),v));}
            if(predictions.isEmpty())continue;var met=metrics(predictions);if(predictor.equals("ZERO_RETURN"))zero=met.mae();var costs=new ArrayList<Cost>();
            for(int bps:List.of(0,25,50,100)){double sum=0;int n=0;for(var r:predictions)if(r.predicted()>bps/100.0){sum=finite(sum+finite(r.observed()-bps/100.0));n++;}costs.add(new Cost(bps,n,n==0?null:sum/n));}
            comparisons.add(new Comparison(predictor,List.copyOf(predictions),met,improvement(zero,met.mae()),List.copyOf(costs)));
        }
        return new Evaluation(inputRows,common.size(),100.0*common.size()/inputRows,List.copyOf(excluded),List.copyOf(comparisons));
    }
    static Manifest fixtureManifest(int expansion) {
        // Explicit synthetic sessions, not a claimed Indian exchange calendar.
        var sessions=new ArrayList<LocalDate>();for(int i=0;i<250;i++)sessions.add(LocalDate.of(2020,1,1).plusDays(i));
        int end=49+expansion*10;return new Manifest(sessions,Map.of(Partition.TRAIN,new Window(sessions.get(0),sessions.get(end)),Partition.VALIDATION,new Window(sessions.get(end+21),sessions.get(end+30)),Partition.TEST,new Window(sessions.get(end+51),sessions.get(end+60))),List.of(),false,20);
    }
    static Map<String,Double> fixtureFeatures(int day,int stock) {
        var x=new LinkedHashMap<String,Double>();for(int j=0;j<10;j++){double v= j==9?50 : j==5?50+10*Math.sin(day+stock) : j==6?2+Math.abs(Math.sin(day*0.7+stock)) : j==7?10+Math.abs(Math.cos(day+stock)) : j==8?1+0.2*Math.sin(day+stock) : Math.sin(day*(j+1)*0.37+stock*1.1)*(j+1);x.put(FEATURES.get(j),v);}return x;
    }
    static List<Row> fixture(Manifest m,String scenario) {
        var rows=new ArrayList<Row>();for(var part:Partition.values()){var w=m.windows().get(part);for(var d=m.sessions().indexOf(w.first());d<=m.sessions().indexOf(w.last());d++)for(int stock=0;stock<(d%3==0?3:2);stock++) {
            var f=fixtureFeatures(d,stock);double y=1+2*f.get(FEATURES.get(0))-0.5*f.get(FEATURES.get(1));
            if(scenario.equals("FLAT"))y=0;if(scenario.equals("REVERSAL") && part==Partition.TEST)y=-y;
            var t=instant(m.sessions().get(d));var end=instant(m.sessions().get(d+20));rows.add(new Row(new Input("SYNTHETIC_"+stock,t,t.minusSeconds(60),f),y,end,end,part,true,POLICY));
        }}return rows;
    }
    static Fold runFold(String scenario,int expansion,String revision) {
        long start=System.nanoTime();var manifest=fixtureManifest(expansion);var rows=fixture(manifest,scenario);var prepared=prepare(manifest,rows);var model=fit(manifest,rows,revision);String artifact=encode(model);var reloaded=decode(artifact,model.metadata());
        for(var r:prepared.eligible())if(r.partition()!=Partition.TRAIN)close(predict(model,r.input()),predict(reloaded,r.input()));
        return new Fold(scenario,sha(json(rows)),manifest,model,artifact,sha(artifact),rows.size(),prepared.excluded(),evaluate(model,prepared,Partition.VALIDATION),evaluate(model,prepared,Partition.TEST),(System.nanoTime()-start)/1e6);
    }
    static void close(double a,double b) {require(Double.isFinite(a) && Double.isFinite(b) && Math.abs(a-b)<=TOLERANCE*Math.max(1,Math.max(Math.abs(a),Math.abs(b))),"NUMERIC_EXPECTATION: "+a+" vs "+b);}
    static void rejects(Runnable action) {boolean rejected=false;try{action.run();}catch(IllegalArgumentException e){rejected=true;}require(rejected,"EXPECTED_REJECTION");}
    static void check(List<Check> checks,String name,Runnable action) {long start=System.nanoTime();String error=null;try{action.run();}catch(RuntimeException e){error=e.toString();}checks.add(new Check(name,error==null,(System.nanoTime()-start)/1e6,error));}
    static Row replace(Row r,Input i,Double target,Instant end,Instant available,String policy) {return new Row(i,target,end,available,r.partition(),r.inspected(),policy);}
    static Map<String,Object> suite(String revision) {
        long start=System.nanoTime();var checks=new ArrayList<Check>();var folds=new ArrayList<Fold>();
        for(int i=0;i<3;i++){String scenario=List.of("LINEAR","FLAT","REVERSAL").get(i);int expansion=i;check(checks,"fold_"+scenario,()->folds.add(runFold(scenario,expansion,revision)));}
        var m=fixtureManifest(0);var rows=fixture(m,"LINEAR");var model=fit(m,rows,revision);
        check(checks,"heldout_mutation_isolation",()->{var changed=rows.stream().map(r->r.partition()==Partition.TRAIN?r:replace(r,new Input(r.input().instrument(),r.input().decisionAt(),r.input().availableAt(),fixtureFeatures(999,1)),999.0,r.labelEnd(),r.labelAvailable(),POLICY)).toList();require(model.equals(fit(m,changed,revision)),"HELDOUT_AFFECTED_FIT");});
        check(checks,"row_order_invariance",()->{var reversed=new ArrayList<>(rows);Collections.reverse(reversed);require(model.equals(fit(m,reversed,revision)),"ORDER_AFFECTED_FIT");});
        check(checks,"date_weights_sum_one",()->{var train=prepare(m,rows).eligible().stream().filter(r->r.partition()==Partition.TRAIN).toList();double[] w=weights(train);close(Arrays.stream(w).sum(),1);var sums=new HashMap<LocalDate,Double>();for(int i=0;i<w.length;i++)sums.merge(date(train.get(i).input().decisionAt()),w[i],Double::sum);sums.values().forEach(v->close(v,1.0/sums.size()));});
        check(checks,"constant_feature",()->{require(model.constants().get(9),"CONSTANT_NOT_RECORDED");close(model.scales().get(9),1);close(model.coefficients().get(9),0);});
        check(checks,"artifact_roundtrip",()->require(model.equals(decode(encode(model),model.metadata())),"ARTIFACT_CHANGED"));
        check(checks,"artifact_corruption",()->rejects(()->decode("0".repeat(64)+encode(model).substring(64),model.metadata())));
        check(checks,"artifact_identity",()->{var identity=new TreeMap<>(model.metadata());identity.put("codeRevision","OTHER");rejects(()->decode(encode(model),identity));});
        check(checks,"duplicate_rows",()->{var bad=new ArrayList<>(rows);bad.add(rows.getFirst());rejects(()->prepare(m,bad));});
        for(String reason:List.of("UNKNOWN_AVAILABILITY","FUTURE_AVAILABILITY","FEATURE_SCHEMA_MISMATCH","MISSING_OR_NON_FINITE_FEATURE","UNCERTIFIED_OR_MARKET_DATA_DISABLED","UNKNOWN_LABEL_AVAILABILITY","LABEL_POLICY_MISMATCH"))check(checks,reason,()->{
            var bad=new ArrayList<>(rows);var r=bad.getFirst();var i=r.input();var f=new LinkedHashMap<>(i.features());Instant avail=i.availableAt(),end=r.labelEnd(),labelAvail=r.labelAvailable();String policy=POLICY;
            switch(reason){case "UNKNOWN_AVAILABILITY"->avail=null;case "FUTURE_AVAILABILITY"->avail=i.decisionAt().plusSeconds(1);case "FEATURE_SCHEMA_MISMATCH"->f.put("actualRank",1.0);case "MISSING_OR_NON_FINITE_FEATURE"->f.put(FEATURES.getFirst(),Double.NaN);case "UNCERTIFIED_OR_MARKET_DATA_DISABLED"->policy="REAL_MARKET";case "UNKNOWN_LABEL_AVAILABILITY"->labelAvail=null;case "LABEL_POLICY_MISMATCH"->end=end.plusSeconds(1);default->throw new IllegalStateException();}
            bad.set(0,replace(r,new Input(i.instrument(),i.decisionAt(),avail,f),r.target(),end,labelAvail,policy));var result=prepare(m,bad);require(result.excluded().size()==1 && result.excluded().getFirst().reason().equals(reason) && result.inputRows()==rows.size(),"MISSING_EXCLUSION");
        });
        for(var part:List.of(Partition.TRAIN,Partition.VALIDATION))check(checks,"label_purge_"+part,()->{var bad=new ArrayList<>(rows);int index=0;while(bad.get(index).partition()!=part)index++;var r=bad.get(index);bad.set(index,replace(r,r.input(),r.target(),r.labelEnd(),Instant.parse("2030-01-01T00:00:00Z"),POLICY));require(prepare(m,bad).excluded().getFirst().reason().equals("PURGED_LABEL_OVERLAP"),"PURGE_NOT_ENFORCED");});
        check(checks,"inspected_final_test",()->rejects(()->prepare(new Manifest(m.sessions(),m.windows(),List.of(m.windows().get(Partition.TEST)),true,20),rows)));
        check(checks,"insufficient_gap",()->rejects(()->prepare(new Manifest(m.sessions(),m.windows(),List.of(),false,19),rows)));
        check(checks,"missing_inference_target_not_required",()->require(Double.isFinite(predict(model,rows.stream().filter(r->r.partition()==Partition.TEST).findFirst().orElseThrow().input())),"NO_PREDICTION"));
        check(checks,"non_finite_solver",()->{double[][] a=new double[10][10];for(int i=0;i<10;i++)a[i][i]=Double.MAX_VALUE;double[] b=new double[10];Arrays.fill(b,Double.MAX_VALUE);rejects(()->solve(a,b));});
        check(checks,"zero_baseline_unavailable",()->require(improvement(0,0)==null,"INVENTED_IMPROVEMENT"));
        check(checks,"abstention_coverage",()->{var bad=new ArrayList<>(rows);int idx=0;while(bad.get(idx).partition()!=Partition.TEST)idx++;var r=bad.get(idx);var f=new LinkedHashMap<>(r.input().features());f.put(FEATURES.get(0),null);bad.set(idx,replace(r,new Input(r.input().instrument(),r.input().decisionAt(),r.input().availableAt(),f),r.target(),r.labelEnd(),r.labelAvailable(),POLICY));var ev=evaluate(model,prepare(m,bad),Partition.TEST);require(ev.evaluatedRows()==ev.inputRows()-1 && ev.exclusions().size()==1 && ev.comparisons().stream().allMatch(c->c.predictions().size()==ev.evaluatedRows()),"ABSTENTION_HIDDEN");});
        check(checks,"negative_result_retained",()->{var fold=folds.stream().filter(f->f.name().equals("REVERSAL")).findFirst().orElseThrow();require(fold.test().comparisons().get(2).maeImprovementVsZeroPercent()<0,"LOSS_HIDDEN");});
        check(checks,"independent_metric_arithmetic",()->{var t=instant(LocalDate.of(2020,1,1));var met=metrics(List.of(new Prediction("A",t,0,1),new Prediction("B",t,0,3),new Prediction("A",t.plusSeconds(86400),0,-3)));close(met.mae(),2.5);close(met.rmse(),Math.sqrt(7));close(met.signedBias(),-0.5);close(met.directionAgreementPercent(),0);});
        check(checks,"collinear_hand_solution",()->{double[][] a=new double[10][10];double[] b=new double[10];for(int i=0;i<10;i++)a[i][i]=ALPHA;a[0][0]+=1;a[1][1]+=1;a[0][1]=a[1][0]=1;b[0]=b[1]=2;var x=solve(a,b);close(x[0],2/(2+ALPHA));close(x[1],2/(2+ALPHA));});
        var uncertaintyReports=new ArrayList<Uncertainty>();
        check(checks,"paired_date_blocks_reproducible",()->{for(var f:folds){var base=f.test().comparisons().get(0).predictions();var challenger=f.test().comparisons().get(2).predictions();var u=uncertainty(base,challenger,2,200,42,0.95);require(u.equals(uncertainty(base,challenger,2,200,42,0.95)),"RESAMPLING_NOT_REPRODUCIBLE");uncertaintyReports.add(u);}});
        check(checks,"unpaired_uncertainty_rejected",()->{var b=folds.getFirst().test().comparisons().getFirst().predictions();rejects(()->uncertainty(b,b.subList(1,b.size()),2,200,42,0.95));});
        check(checks,"constant_block_oracle",()->{var b=new ArrayList<Prediction>();var c=new ArrayList<Prediction>();for(int day=0;day<8;day++)for(int stock=0;stock<=day%3;stock++){var t=instant(LocalDate.of(2020,1,1).plusDays(day));b.add(new Prediction("S"+stock,t,0,3));c.add(new Prediction("S"+stock,t,0,1));}var u=uncertainty(b,c,2,200,42,0.95);close(u.lower(),2);close(u.upper(),2);close(u.meanErrorReduction(),2);});
        var report=new TreeMap<String,Object>();report.put("version",VERSION);report.put("checks",checks);report.put("checkCount",checks.size());report.put("failedCheckCount",checks.stream().filter(c->!c.passed()).count());report.put("folds",folds);
        report.put("status",checks.stream().allMatch(Check::passed)?"SYNTHETIC_CHECKS_PASSED":"SYNTHETIC_CHECKS_FAILED");
        report.put("syntheticOnly",true);report.put("realMarketTrainingAuthorized",false);report.put("automaticPromotionEnabled",false);report.put("actionExecutionEnabled",false);report.put("databaseWritesPerformed",false);
        report.put("providerCallCount",0);report.put("llmCallCount",0);report.put("ordersCreated",0);report.put("signalsCreated",0);report.put("elapsedMillis",(System.nanoTime()-start)/1e6);
        report.put("configuration",Map.of("featureOrder",FEATURES,"featureUnits",UNITS,"alpha",ALPHA,"parityTolerance",TOLERANCE,"horizonSessions",20,"costsBps",List.of(0,25,50,100)));
        report.put("syntheticUncertaintyChecks",uncertaintyReports);
        report.put("readiness",Map.of("status","MARKET_FIT_BLOCKED","trainingEligibleMarketRows",0,"uncertainty","UNAVAILABLE_SYNTHETIC_ENGINEERING_NOT_MARKET_EVIDENCE","blockers",List.of("SOURCE_PRICE_ACTION_EVIDENCE","HISTORICAL_AVAILABILITY","SOURCE_RIGHTS","FINAL_EVALUATION_CRITERIA","SCOPED_MARKET_FIT_APPROVAL")));
        return report;
    }
    static String sha(String s) {try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    static String json(Object value) {
        if(value==null)return "null";if(value instanceof Number n){finite(n.doubleValue());return n.toString();}if(value instanceof Boolean)return value.toString();
        if(value instanceof Map<?,?> map){var sorted=new TreeMap<String,Object>();map.forEach((k,v)->sorted.put(k.toString(),v));return "{"+String.join(",",sorted.entrySet().stream().map(e->json(e.getKey())+":"+json(e.getValue())).toList())+"}";}
        if(value instanceof Collection<?> list)return "["+String.join(",",list.stream().map(NumericalTenFeatureEngineering::json).toList())+"]";
        if(value.getClass().isRecord()){var map=new TreeMap<String,Object>();try{for(RecordComponent c:value.getClass().getRecordComponents())map.put(c.getName(),c.getAccessor().invoke(value));}catch(Exception e){throw new IllegalStateException(e);}return json(map);}
        String s=value.toString();var b=new StringBuilder("\"");for(char c:s.toCharArray()){switch(c){case '"'->b.append("\\\"");case '\\'->b.append("\\\\");case '\n'->b.append("\\n");case '\r'->b.append("\\r");case '\t'->b.append("\\t");default->{if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);}}}return b.append('"').toString();
    }
    public static void main(String[] args) {
        require(args.length==2 && "--synthetic-suite".equals(args[0]),"ONLY_FIXED_SYNTHETIC_SUITE_ALLOWED");
        var result=suite(args[1]);System.out.println(json(result));if(!"SYNTHETIC_CHECKS_PASSED".equals(result.get("status")))System.exit(1);
    }
}
