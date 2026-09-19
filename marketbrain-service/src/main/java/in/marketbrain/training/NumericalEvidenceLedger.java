package in.marketbrain.training;

import java.io.*;
import java.lang.reflect.RecordComponent;
import java.nio.ByteBuffer;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** Append-only evidence infrastructure. No bean, feed, scheduler, learner or trade consumer.
 * CLI accepts only fixed synthetic persistence tests, never a market payload/path. */
public final class NumericalEvidenceLedger {
    static final String VERSION="NUMERICAL_EVIDENCE_LEDGER_V1";
    static final int MAGIC=0x4d424531, MAX_PAYLOAD=32768;
    static final String GENESIS="0".repeat(64);
    static final List<String> FEATURES=List.of("dailyReturnPercent","closeToSma20Percent","closeToSma50Percent",
            "closeToSma200Percent","ema12ToEma26Percent","rsi14","atr14ToClosePercent",
            "annualizedVolatility20Percent","volumeRatio20","rangePosition252Percent");
    static final List<String> UNITS=List.of("PERCENT","PERCENT","PERCENT","PERCENT","PERCENT","INDEX_0_100","PERCENT","PERCENT","RATIO","PERCENT_0_100");
    record Policy(long maxFeatureAgeSeconds,long maxClockSkewMillis,int maxRecords,long maxStoreBytes) {
        Policy { require(maxFeatureAgeSeconds>0 && maxFeatureAgeSeconds<=86400 && maxClockSkewMillis>=0 && maxClockSkewMillis<=60000,"INVALID_TIME_LIMITS");
            require(maxRecords>0 && maxRecords<=10000 && maxStoreBytes>=1024 && maxStoreBytes<=64*1024*1024,"INVALID_STORAGE_LIMITS"); }
    }
    record Snapshot(long instrumentId,String symbol,String universeVersion,String provider,String sourceRevision,
                    Instant providerEventAt,Instant receivedAt,Instant decisionAt,Instant inputAvailableAt,
                    boolean clockHealthy,long clockSkewMillis,List<String> rawInputHashes,String calendarHash,
                    String priceActionPolicyHash,String calculatorRevision,String rightsScopeId,
                    Map<String,Double> features,List<String> qualityFlags,String supersedesId) {
        Snapshot {
            require(instrumentId>0,"INVALID_INSTRUMENT");for(String s:List.of(symbol,universeVersion,provider,sourceRevision,calculatorRevision))token(s);
            require(receivedAt!=null && decisionAt!=null,"MISSING_RECEIPT_OR_DECISION");
            for(Instant at:Arrays.asList(providerEventAt,receivedAt,decisionAt,inputAvailableAt))if(at!=null)require(!at.isBefore(Instant.parse("1900-01-01T00:00:00Z")) && at.isBefore(Instant.parse("2200-01-01T00:00:00Z")),"TIMESTAMP_OUT_OF_BOUNDS");
            require(clockSkewMillis!=Long.MIN_VALUE,"INVALID_CLOCK_SKEW");
            require(rawInputHashes!=null && !rawInputHashes.isEmpty() && rawInputHashes.size()<=16,"INVALID_INPUT_HASHES");
            rawInputHashes=rawInputHashes.stream().sorted().toList();require(new HashSet<>(rawInputHashes).size()==rawInputHashes.size(),"DUPLICATE_INPUT_HASH");rawInputHashes.forEach(NumericalEvidenceLedger::hash);
            hash(calendarHash);if(priceActionPolicyHash!=null)hash(priceActionPolicyHash);if(rightsScopeId!=null)token(rightsScopeId);if(supersedesId!=null)hash(supersedesId);
            require(features!=null && new HashSet<>(FEATURES).containsAll(features.keySet()),"UNKNOWN_FEATURE_OR_OUTCOME");
            for(var v:features.values())require(v==null || Double.isFinite(v),"NON_FINITE_FEATURE");features=Collections.unmodifiableMap(new TreeMap<>(features));
            require(qualityFlags!=null && qualityFlags.size()<=32,"INVALID_QUALITY_FLAGS");qualityFlags.forEach(NumericalEvidenceLedger::token);
            qualityFlags=qualityFlags.stream().distinct().sorted().toList();
        }
    }
    record Assessment(String status,List<String> reasons,boolean trainingEligible,boolean collectionAuthorized) { }
    record Entry(int sequence,String previousHash,String entryHash,String snapshotId,String decisionKey,
                 String disposition,Snapshot snapshot,Assessment assessment) { }
    record Audit(String status,List<Entry> entries,int validPrefixBytes,int totalBytes,String fileHash) { }
    record AppendResult(String disposition,Entry entry,boolean appended) { }
    record Recovery(String status,String sourceFileHash,int preservedSourceBytes,int recoveredEntries,
                    int recoveredPrefixBytes,String recoveredFileHash) { }
    record Check(String name,boolean passed,double elapsedMillis,String failure) { }
    static void require(boolean ok,String reason){if(!ok)throw new IllegalArgumentException(reason);}
    static void token(String s){require(s!=null && s.matches("[A-Za-z0-9_.:-]{1,100}"),"INVALID_METADATA_TOKEN");}
    static void hash(String s){require(s!=null && s.matches("[a-f0-9]{64}"),"INVALID_SHA256");}
    static String sha(byte[] bytes){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(Exception e){throw new IllegalStateException(e);}}
    static String sha(String text){return sha(text.getBytes(StandardCharsets.UTF_8));}
    static String key(Snapshot s){return s.instrumentId()+"@"+s.decisionAt()+"@"+VERSION;}
    static Assessment assess(Snapshot s,Policy p){
        var reasons=new ArrayList<String>();
        if(s.providerEventAt()==null)reasons.add("PROVIDER_EVENT_TIME_UNKNOWN");
        if(s.providerEventAt()!=null && s.providerEventAt().isAfter(s.receivedAt()))reasons.add("PROVIDER_EVENT_AFTER_RECEIPT");
        if(s.providerEventAt()!=null && s.providerEventAt().isBefore(s.decisionAt().minusSeconds(p.maxFeatureAgeSeconds())))reasons.add("STALE_PROVIDER_EVENT");
        if(s.receivedAt().isAfter(s.decisionAt()))reasons.add("RECEIVED_AFTER_DECISION");
        if(s.inputAvailableAt()==null)reasons.add("INPUT_AVAILABILITY_UNKNOWN");
        else {
            if(s.inputAvailableAt().isAfter(s.decisionAt()))reasons.add("INPUT_AVAILABLE_AFTER_DECISION");
            if(s.inputAvailableAt().isBefore(s.receivedAt()))reasons.add("INPUT_AVAILABLE_BEFORE_RECEIPT");
            if(s.inputAvailableAt().isBefore(s.decisionAt().minusSeconds(p.maxFeatureAgeSeconds())))reasons.add("STALE_INPUT");
        }
        if(!s.clockHealthy() || Math.abs(s.clockSkewMillis())>p.maxClockSkewMillis())reasons.add("CLOCK_UNTRUSTED");
        if(!s.features().keySet().equals(new HashSet<>(FEATURES)) || s.features().values().contains(null))reasons.add("FEATURES_INCOMPLETE");
        if(s.priceActionPolicyHash()==null)reasons.add("PRICE_ACTION_POLICY_MISSING");
        if(s.rightsScopeId()==null)reasons.add("RIGHTS_SCOPE_MISSING");
        if(!s.qualityFlags().isEmpty())reasons.add("SOURCE_QUALITY_FLAGS");
        // Structural time/order validation is not external source authenticity or runtime authorization.
        return new Assessment(reasons.isEmpty()?"DECLARED_STRUCTURE_VALID_NOT_CERTIFIED":"QUARANTINED_DATA_QUALITY",List.copyOf(reasons),false,false);
    }
    static void text(DataOutputStream out,String value)throws IOException{out.writeBoolean(value!=null);if(value!=null)out.writeUTF(value);}
    static String text(DataInputStream in)throws IOException{return in.readBoolean()?in.readUTF():null;}
    static void time(DataOutputStream out,Instant value)throws IOException{text(out,value==null?null:value.toString());}
    static Instant time(DataInputStream in)throws IOException{String s=text(in);return s==null?null:Instant.parse(s);}
    static byte[] snapshotBytes(Snapshot s){
        try{var bytes=new ByteArrayOutputStream();var out=new DataOutputStream(bytes);
            out.writeUTF(VERSION);out.writeLong(s.instrumentId());for(var v:List.of(s.symbol(),s.universeVersion(),s.provider(),s.sourceRevision()))out.writeUTF(v);
            time(out,s.providerEventAt());time(out,s.receivedAt());time(out,s.decisionAt());time(out,s.inputAvailableAt());out.writeBoolean(s.clockHealthy());out.writeLong(s.clockSkewMillis());
            out.writeInt(s.rawInputHashes().size());for(var h:s.rawInputHashes())out.writeUTF(h);out.writeUTF(s.calendarHash());text(out,s.priceActionPolicyHash());out.writeUTF(s.calculatorRevision());text(out,s.rightsScopeId());
            out.writeInt(s.features().size());for(var e:s.features().entrySet()){out.writeUTF(e.getKey());out.writeBoolean(e.getValue()!=null);if(e.getValue()!=null)out.writeDouble(e.getValue());}
            out.writeInt(s.qualityFlags().size());for(var flag:s.qualityFlags())out.writeUTF(flag);text(out,s.supersedesId());out.flush();require(bytes.size()<MAX_PAYLOAD,"SNAPSHOT_TOO_LARGE");return bytes.toByteArray();
        }catch(IOException e){throw new IllegalStateException(e);}
    }
    static Snapshot snapshot(byte[] bytes)throws IOException{
        var in=new DataInputStream(new ByteArrayInputStream(bytes));require(in.readUTF().equals(VERSION),"SCHEMA_MISMATCH");
        long id=in.readLong();String symbol=in.readUTF(),universe=in.readUTF(),provider=in.readUTF(),revision=in.readUTF();
        Instant event=time(in),received=time(in),decision=time(in),available=time(in);boolean healthy=in.readBoolean();long skew=in.readLong();
        int n=in.readInt();require(n>0 && n<=16,"HASH_COUNT");var hashes=new ArrayList<String>();for(int i=0;i<n;i++)hashes.add(in.readUTF());
        String calendar=in.readUTF(),prices=text(in),calculator=in.readUTF(),rights=text(in);
        n=in.readInt();require(n>=0 && n<=10,"FEATURE_COUNT");var features=new TreeMap<String,Double>();
        for(int i=0;i<n;i++){String k=in.readUTF();require(!features.containsKey(k),"DUPLICATE_FEATURE");features.put(k,in.readBoolean()?in.readDouble():null);}
        n=in.readInt();require(n>=0 && n<=32,"QUALITY_COUNT");var quality=new ArrayList<String>();for(int i=0;i<n;i++)quality.add(in.readUTF());String prior=text(in);require(in.read()==-1,"SNAPSHOT_TRAILING_BYTES");
        var s=new Snapshot(id,symbol,universe,provider,revision,event,received,decision,available,healthy,skew,hashes,calendar,prices,calculator,rights,features,quality,prior);
        require(Arrays.equals(bytes,snapshotBytes(s)),"NON_CANONICAL_SNAPSHOT");return s;
    }
    static byte[] header(Policy policy){try{var b=new ByteArrayOutputStream();var out=new DataOutputStream(b);out.writeInt(MAGIC);out.writeUTF(VERSION);out.writeUTF(sha(json(policy)));out.writeUTF(sha(json(List.of(FEATURES,UNITS))));out.flush();return b.toByteArray();}catch(IOException e){throw new IllegalStateException(e);}}
    static byte[] payload(int seq,String previous,String disposition,Snapshot s){try{var b=new ByteArrayOutputStream();var out=new DataOutputStream(b);out.writeInt(seq);out.writeUTF(previous);out.writeUTF(disposition);byte[] sb=snapshotBytes(s);out.writeInt(sb.length);out.write(sb);out.flush();return b.toByteArray();}catch(IOException e){throw new IllegalStateException(e);}}
    static byte[] frame(byte[] payload){try{var b=new ByteArrayOutputStream();var out=new DataOutputStream(b);out.writeInt(payload.length);out.write(payload);out.write(HexFormat.of().parseHex(sha(payload)));out.flush();return b.toByteArray();}catch(IOException e){throw new IllegalStateException(e);}}
    static String disposition(List<Entry> entries,Snapshot s,String id){
        if(entries.stream().anyMatch(e->e.snapshotId().equals(id)))return "DUPLICATE_NO_WRITE";
        var same=entries.stream().filter(e->e.decisionKey().equals(key(s))).toList();
        if(s.supersedesId()!=null){require(same.stream().anyMatch(e->e.snapshotId().equals(s.supersedesId())),"UNKNOWN_OR_WRONG_DECISION_CORRECTION");return "CORRECTION_RECORDED_REVIEW_REQUIRED";}
        return same.isEmpty()?"ORIGINAL_RECORDED":"QUARANTINED_CONFLICT";
    }
    /** One data file + coordination lock. Existing bytes are never truncated, deleted or overwritten. */
    static final class Store {
        final Path directory,data,lockPath;final Policy policy;
        Store(Path directory,Policy policy)throws IOException {
            this.directory=directory.toAbsolutePath().normalize();this.policy=Objects.requireNonNull(policy);
            require(this.directory.getParent()!=null,"ROOT_DIRECTORY_NOT_ALLOWED");
            for(Path p=this.directory;p!=null;p=p.getParent())require(!Files.isSymbolicLink(p),"SYMLINK_DIRECTORY");
            Files.createDirectories(this.directory);require(this.directory.toRealPath().equals(this.directory),"REDIRECTED_DIRECTORY");
            data=this.directory.resolve("evidence.bin");lockPath=this.directory.resolve("evidence.lock");safePaths();
        }
        void safePaths()throws IOException{
            require(directory.toRealPath().equals(directory),"DIRECTORY_CHANGED");
            for(Path p:List.of(data,lockPath))require(!Files.exists(p,LinkOption.NOFOLLOW_LINKS) || Files.isRegularFile(p,LinkOption.NOFOLLOW_LINKS),"NON_REGULAR_LEDGER_FILE");
        }
        interface Work<T>{T run()throws IOException;}
        <T>T locked(Work<T> work)throws IOException{
            safePaths();try(var channel=FileChannel.open(lockPath,StandardOpenOption.CREATE,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){
                FileLock lock;try{lock=channel.tryLock();}catch(OverlappingFileLockException e){throw new IllegalArgumentException("LEDGER_BUSY",e);}require(lock!=null,"LEDGER_BUSY");
                try(lock){return work.run();}
            }
        }
        byte[] readBytes()throws IOException{
            if(!Files.exists(data,LinkOption.NOFOLLOW_LINKS))return new byte[0];
            require(Files.size(data)<=policy.maxStoreBytes(),"STORE_BYTE_LIMIT");
            // Read under our lock with a hard byte cap even if a non-cooperating writer changes the file.
            try(var in=Files.newInputStream(data,LinkOption.NOFOLLOW_LINKS)){byte[] b=in.readNBytes(Math.toIntExact(policy.maxStoreBytes()+1));require(b.length<=policy.maxStoreBytes(),"STORE_BYTE_LIMIT");return b;}
        }
        Audit audit()throws IOException{return locked(()->auditBytes(readBytes(),policy));}
        AppendResult append(Snapshot s)throws IOException{return locked(()->{
            byte[] bytes=readBytes();Audit audit=auditBytes(bytes,policy);require(audit.status().equals("COMPLETE") || audit.status().equals("EMPTY_NEW_STORE"),"LEDGER_NOT_APPENDABLE: "+audit.status());
            Assessment assessment=assess(s,policy);String id=sha(snapshotBytes(s)),status=disposition(audit.entries(),s,id);
            if(status.equals("DUPLICATE_NO_WRITE"))return new AppendResult(status,audit.entries().stream().filter(e->e.snapshotId().equals(id)).findFirst().orElseThrow(),false);
            require(audit.entries().size()<policy.maxRecords(),"STORE_RECORD_LIMIT");
            int seq=audit.entries().size()+1;String prev=audit.entries().isEmpty()?GENESIS:audit.entries().getLast().entryHash();byte[] payload=payload(seq,prev,status,s),frame=frame(payload),prefix=bytes.length==0?header(policy):new byte[0];
            require((long)bytes.length+prefix.length+frame.length<=policy.maxStoreBytes(),"STORE_BYTE_LIMIT");
            if(bytes.length==0)try(var out=FileChannel.open(data,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){write(out,prefix);write(out,frame);out.force(true);}
            else try(var out=FileChannel.open(data,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){require(out.size()==bytes.length,"STORE_CHANGED");out.position(bytes.length);write(out,frame);out.force(true);}
            var entry=new Entry(seq,prev,sha(payload),id,key(s),status,s,assessment);return new AppendResult(status,entry,true);
        });}
        Recovery recoverTo(Path newDirectory)throws IOException{return locked(()->{
            byte[] bytes=readBytes();Audit audit=auditBytes(bytes,policy);require(audit.status().equals("INCOMPLETE_TAIL"),"ONLY_INCOMPLETE_TAIL_RECOVERY_ALLOWED");
            require(audit.validPrefixBytes()>=header(policy).length,"NO_VALID_HEADER");
            Path destination=newDirectory.toAbsolutePath().normalize();require(!Files.exists(destination,LinkOption.NOFOLLOW_LINKS),"RECOVERY_DESTINATION_MUST_BE_NEW");
            var target=new Store(destination,policy);target.locked(()->{try(var out=FileChannel.open(target.data,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){write(out,Arrays.copyOf(bytes,audit.validPrefixBytes()));out.force(true);}return null;});
            var verified=target.audit();require(verified.status().equals("COMPLETE"),"RECOVERY_VERIFY_FAILED");
            // A recovery receipt binds the original incomplete file. It is metadata, not an authorization.
            var result=new Recovery("RECOVERED_TO_NEW_STORE_ORIGINAL_PRESERVED",audit.fileHash(),bytes.length,verified.entries().size(),audit.validPrefixBytes(),verified.fileHash());
            Files.writeString(destination.resolve("recovery.json"),json(result),StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
            return result;
        });}
    }
    static void write(FileChannel out,byte[] bytes)throws IOException{var b=ByteBuffer.wrap(bytes);while(b.hasRemaining())out.write(b);}
    static Audit auditBytes(byte[] bytes,Policy policy){
        require(bytes!=null && bytes.length<=policy.maxStoreBytes(),"STORE_BYTE_LIMIT");
        var entries=new ArrayList<Entry>();int valid=0;String status="COMPLETE";
        if(bytes.length==0)return new Audit("EMPTY_NEW_STORE",List.of(),0,0,sha(bytes));
        byte[] expected=header(policy);
        if(bytes.length<expected.length)return new Audit("INCOMPLETE_HEADER",List.of(),0,bytes.length,sha(bytes));
        if(!Arrays.equals(Arrays.copyOf(bytes,expected.length),expected))return new Audit("HEADER_OR_POLICY_MISMATCH",List.of(),0,bytes.length,sha(bytes));
        valid=expected.length;
        while(valid<bytes.length){
            int remaining=bytes.length-valid;if(remaining<4){status="INCOMPLETE_TAIL";break;}
            int length=ByteBuffer.wrap(bytes,valid,4).getInt();
            if(length<1 || length>MAX_PAYLOAD){status="CORRUPT_FRAME_LENGTH";break;}
            if((long)remaining<4L+length+32){status="INCOMPLETE_TAIL";break;}
            byte[] payload=Arrays.copyOfRange(bytes,valid+4,valid+4+length);String digest=sha(payload);
            if(!Arrays.equals(HexFormat.of().parseHex(digest),Arrays.copyOfRange(bytes,valid+4+length,valid+4+length+32))){status="CORRUPT_CHECKSUM";break;}
            try{
                var in=new DataInputStream(new ByteArrayInputStream(payload));int seq=in.readInt();String prev=in.readUTF(),kind=in.readUTF();int n=in.readInt();require(n>0 && n<=MAX_PAYLOAD,"SNAPSHOT_SIZE");byte[] sb=in.readNBytes(n);require(sb.length==n && in.read()==-1,"FRAME_TRAILING_BYTES");Snapshot s=snapshot(sb);
                require(seq==entries.size()+1 && prev.equals(entries.isEmpty()?GENESIS:entries.getLast().entryHash()),"CHAIN_MISMATCH");String id=sha(sb),expectedKind=disposition(entries,s,id);
                require(!expectedKind.equals("DUPLICATE_NO_WRITE") && expectedKind.equals(kind),"DISPOSITION_MISMATCH");require(entries.size()<policy.maxRecords(),"RECORD_LIMIT");
                entries.add(new Entry(seq,prev,digest,id,key(s),kind,s,assess(s,policy)));valid+=4+length+32;
            }catch(IOException|RuntimeException e){status="CORRUPT_ENTRY";break;}
        }
        return new Audit(status,List.copyOf(entries),valid,bytes.length,sha(bytes));
    }
    static Snapshot fixture(int index){
        Instant decision=Instant.parse("2026-01-05T10:30:00Z").plusSeconds(index*86400L);var features=new TreeMap<String,Double>();for(int i=0;i<FEATURES.size();i++)features.put(FEATURES.get(i),(double)i);
        return new Snapshot(2,"SYNTHETIC","TEST_UNIVERSE","FIXTURE","V1",decision.minusSeconds(10),decision.minusSeconds(5),decision,decision.minusSeconds(4),true,0,List.of(sha("raw-"+index)),sha("calendar"),sha("price"),"CALCULATOR_V1","FIXTURE_RIGHTS",features,List.of(),null);
    }
    static Snapshot change(Snapshot s,Instant event,Instant received,Instant available,boolean clock,long skew,Map<String,Double> features,String prior,String rights,String price,List<String> flags){
        return new Snapshot(s.instrumentId(),s.symbol(),s.universeVersion(),s.provider(),s.sourceRevision(),event,received,s.decisionAt(),available,clock,skew,s.rawInputHashes(),s.calendarHash(),price,s.calculatorRevision(),rights,features,flags,prior);
    }
    interface CheckedWork{void run()throws Exception;}
    static void rejected(CheckedWork work)throws Exception{boolean rejected=false;try{work.run();}catch(IllegalArgumentException e){rejected=true;}require(rejected,"EXPECTED_REJECTION");}
    static void check(List<Check> checks,String name,CheckedWork work){long start=System.nanoTime();String failure=null;try{work.run();}catch(Exception e){failure=e.toString();}checks.add(new Check(name,failure==null,(System.nanoTime()-start)/1e6,failure));}
    static Map<String,Object> suite(Path root)throws Exception{
        long start=System.nanoTime();var p=new Policy(60,1000,30,128*1024);var s=fixture(0);var checks=new ArrayList<Check>();var store=new Store(root.resolve("main"),p);
        check(checks,"append_and_restart",()->{var a=store.append(s);require(a.appended() && a.entry().sequence()==1,"NOT_APPENDED");var audit=new Store(store.directory,p).audit();require(audit.status().equals("COMPLETE") && audit.entries().getFirst().snapshot().equals(s),"RESTART_PARITY");});
        check(checks,"duplicate_no_write",()->{String before=store.audit().fileHash();require(!store.append(s).appended() && before.equals(store.audit().fileHash()),"DUPLICATE_CHANGED_STORE");});
        var changed=new TreeMap<>(s.features());changed.put(FEATURES.getFirst(),99.0);
        Snapshot conflicting=change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,changed,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        check(checks,"conflict_quarantined",()->require(store.append(conflicting).disposition().equals("QUARANTINED_CONFLICT"),"CONFLICT_NOT_VISIBLE"));
        check(checks,"correction_preserves_original",()->{String original=sha(snapshotBytes(s));var correction=change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,changed,original,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());require(store.append(correction).disposition().equals("CORRECTION_RECORDED_REVIEW_REQUIRED") && store.audit().entries().getFirst().snapshot().equals(s),"ORIGINAL_OVERWRITTEN");});
        check(checks,"unknown_correction_rejected",()->rejected(()->store.append(change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,changed,GENESIS,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()))));
        check(checks,"unknown_availability_quarantined",()->require(assess(change(s,null,s.receivedAt(),null,true,0,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()),p).reasons().containsAll(List.of("PROVIDER_EVENT_TIME_UNKNOWN","INPUT_AVAILABILITY_UNKNOWN")),"UNKNOWN_INFERRED"));
        check(checks,"future_input_quarantined",()->require(assess(change(s,s.providerEventAt(),s.decisionAt().plusSeconds(1),s.decisionAt().plusSeconds(2),true,0,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()),p).reasons().containsAll(List.of("RECEIVED_AFTER_DECISION","INPUT_AVAILABLE_AFTER_DECISION")),"FUTURE_ALLOWED"));
        check(checks,"stale_input_quarantined",()->require(assess(change(s,s.decisionAt().minusSeconds(100),s.decisionAt().minusSeconds(90),s.decisionAt().minusSeconds(80),true,0,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()),p).reasons().contains("STALE_INPUT"),"STALE_ALLOWED"));
        check(checks,"clock_quarantined",()->require(assess(change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),false,1001,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()),p).reasons().contains("CLOCK_UNTRUSTED"),"CLOCK_ALLOWED"));
        check(checks,"rights_and_price_not_inferred",()->require(assess(change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,s.features(),null,null,null,List.of()),p).reasons().containsAll(List.of("RIGHTS_SCOPE_MISSING","PRICE_ACTION_POLICY_MISSING")),"SOURCE_CERTIFIED"));
        check(checks,"missing_features_retained",()->{var f=new TreeMap<>(s.features());f.put(FEATURES.getFirst(),null);var bad=change(fixture(1),fixture(1).providerEventAt(),fixture(1).receivedAt(),fixture(1).inputAvailableAt(),true,0,f,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());var a=store.append(bad);require(a.entry().assessment().reasons().contains("FEATURES_INCOMPLETE") && store.audit().entries().getLast().snapshot().features().containsValue(null),"MISSING_FEATURE_LOST");});
        check(checks,"outcome_feature_rejected",()->{var f=new TreeMap<>(s.features());f.put("actualRank",1.0);rejected(()->change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,f,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()));});
        check(checks,"non_finite_rejected",()->{var f=new TreeMap<>(s.features());f.put(FEATURES.getFirst(),Double.NaN);rejected(()->change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,f,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()));});
        check(checks,"concurrent_writer_fails_fast",()->{try(var c=FileChannel.open(store.lockPath,StandardOpenOption.WRITE);var lock=c.lock()){rejected(()->store.append(fixture(2)));}});
        check(checks,"policy_mismatch_rejected",()->{var other=new Store(store.directory,new Policy(61,1000,30,128*1024));require(other.audit().status().equals("HEADER_OR_POLICY_MISMATCH"),"POLICY_CHANGED");rejected(()->other.append(fixture(2)));});
        check(checks,"record_limit_no_write",()->{var small=new Store(root.resolve("record-limit"),new Policy(60,1000,1,128*1024));small.append(s);String before=small.audit().fileHash();rejected(()->small.append(fixture(2)));require(before.equals(small.audit().fileHash()),"LIMIT_CHANGED_STORE");});
        check(checks,"byte_limit_no_write",()->{long cap=Math.max(1024,header(p).length+frame(payload(1,GENESIS,"ORIGINAL_RECORDED",s)).length);var small=new Store(root.resolve("byte-limit"),new Policy(60,1000,30,cap));small.append(s);String before=small.audit().fileHash();rejected(()->small.append(fixture(2)));require(before.equals(small.audit().fileHash()),"BYTE_LIMIT_CHANGED_DATA");});
        check(checks,"corruption_blocks_append_and_recovery",()->{var bad=new Store(root.resolve("corrupt"),p);bad.append(s);byte[] bytes=Files.readAllBytes(bad.data);bytes[header(p).length+10]^=1;Files.write(bad.data,bytes);require(bad.audit().status().equals("CORRUPT_CHECKSUM"),"CORRUPTION_MISSED");rejected(()->bad.append(fixture(2)));rejected(()->bad.recoverTo(root.resolve("invalid-recovery")));});
        Recovery[] recovery=new Recovery[1];
        check(checks,"partial_tail_new_branch_original_preserved",()->{var partial=new Store(root.resolve("partial"),p);partial.append(s);Files.write(partial.data,new byte[]{0,0},StandardOpenOption.APPEND);byte[] original=Files.readAllBytes(partial.data);require(partial.audit().status().equals("INCOMPLETE_TAIL"),"PARTIAL_MISSED");rejected(()->partial.append(fixture(2)));recovery[0]=partial.recoverTo(root.resolve("recovered"));require(Arrays.equals(original,Files.readAllBytes(partial.data)),"ORIGINAL_CHANGED");var recovered=new Store(root.resolve("recovered"),p);require(recovered.append(fixture(2)).appended() && Files.exists(recovered.directory.resolve("recovery.json")),"RECOVERY_FAILED");});
        check(checks,"recovery_destination_not_overwritten",()->{var partial=new Store(root.resolve("partial"),p);rejected(()->partial.recoverTo(root.resolve("main")));});
        check(checks,"incomplete_header_not_auto_repaired",()->{var bad=new Store(root.resolve("header"),p);Files.write(bad.data,new byte[]{1},StandardOpenOption.CREATE_NEW);require(bad.audit().status().equals("INCOMPLETE_HEADER"),"HEADER_MISSED");rejected(()->bad.append(s));});
        check(checks,"future_outcomes_and_permissions_not_created",()->{for(var e:store.audit().entries())require(!e.assessment().trainingEligible() && !e.assessment().collectionAuthorized(),"GATE_OPENED");});
        var result=new TreeMap<String,Object>();result.put("version",VERSION);result.put("status",checks.stream().allMatch(Check::passed)?"EVIDENCE_CHECKS_PASSED":"EVIDENCE_CHECKS_FAILED");result.put("checks",checks);result.put("checkCount",checks.size());result.put("failedCheckCount",checks.stream().filter(c->!c.passed()).count());
        result.put("syntheticOnly",true);result.put("fixturePolicyNotRuntimeDefaults",p);result.put("audit",store.audit());result.put("recovery",recovery[0]);result.put("elapsedMillis",(System.nanoTime()-start)/1e6);result.put("runtimeVersion",System.getProperty("java.version"));
        result.put("featureOrder",FEATURES);result.put("featureUnits",UNITS);result.put("headerBytes",header(p).length);result.put("ledgerBase64",Base64.getEncoder().encodeToString(Files.readAllBytes(store.data)));
        result.put("marketDataCollectionEnabled",false);result.put("marketFitAuthorized",false);result.put("databaseWritesPerformed",false);result.put("ordersCreated",0);result.put("providerCallCount",0);result.put("llmCallCount",0);result.put("signalsCreated",0);result.put("actionExecutionEnabled",false);return result;
    }
    static String json(Object value){
        if(value==null)return "null";if(value instanceof Number || value instanceof Boolean)return value.toString();
        if(value instanceof Map<?,?> map){var sorted=new TreeMap<String,Object>();map.forEach((k,v)->sorted.put(k.toString(),v));return "{"+String.join(",",sorted.entrySet().stream().map(e->json(e.getKey())+":"+json(e.getValue())).toList())+"}";}
        if(value instanceof Collection<?> list)return "["+String.join(",",list.stream().map(NumericalEvidenceLedger::json).toList())+"]";
        if(value.getClass().isRecord()){var map=new TreeMap<String,Object>();try{for(RecordComponent c:value.getClass().getRecordComponents())map.put(c.getName(),c.getAccessor().invoke(value));}catch(Exception e){throw new IllegalStateException(e);}return json(map);}
        var b=new StringBuilder("\"");for(char c:value.toString().toCharArray()){switch(c){case '"'->b.append("\\\"");case '\\'->b.append("\\\\");case '\n'->b.append("\\n");case '\r'->b.append("\\r");case '\t'->b.append("\\t");default->{if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);}}}return b.append('"').toString();
    }
    public static void main(String[] args)throws Exception{
        require(args.length==1 && args[0].equals("--synthetic-evidence"),"ONLY_FIXED_SYNTHETIC_EVIDENCE_ALLOWED");
        Path root=Files.createTempDirectory("marketbrain-evidence-fixture-");Map<String,Object> result;
        try{result=suite(root);}finally{
            // Only this invocation's explicitly named tiny fixture stores; never enumerate/delete a caller path.
            for(String dir:List.of("main","record-limit","byte-limit","corrupt","partial","recovered","header","invalid-recovery")){
                Path p=root.resolve(dir);for(String name:List.of("evidence.bin","evidence.lock","recovery.json"))Files.deleteIfExists(p.resolve(name));Files.deleteIfExists(p);
            }Files.delete(root);
        }
        System.out.println(json(result));if(!"EVIDENCE_CHECKS_PASSED".equals(result.get("status")))System.exit(1);
    }
}
