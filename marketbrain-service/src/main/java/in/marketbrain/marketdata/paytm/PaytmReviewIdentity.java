package in.marketbrain.marketdata.paytm;

import in.marketbrain.marketdata.universe.CurrentNifty500CsvParser;
import java.io.StringReader;
import java.net.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.*;

/** Fixed public reference sources only. Never accepts a caller-supplied ID, ISIN or price. */
final class PaytmReviewIdentity implements AutoCloseable {
    static final URI PAYTM=URI.create("https://developer.paytmmoney.com/data/v1/scrips/equity_security_master.csv");
    static final URI NIFTY=URI.create("https://www.niftyindices.com/IndexConstituent/ind_nifty500list.csv");
    interface Source {byte[] read(URI uri)throws Exception;}
    private final Source source;
    private final HttpClient client;
    PaytmReviewIdentity(){
        client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build();
        source=uri->{
            if(!PAYTM.equals(uri) && !NIFTY.equals(uri))throw new IllegalArgumentException();
            var response=client.send(HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(15)).GET().build(),i->new PaytmSupervisedClient.BoundedBody(4194304));
            if(response.statusCode()!=200 || response.sslSession().isEmpty())throw new IllegalStateException();
            return response.body();
        };
    }
    PaytmReviewIdentity(Source source){this.source=source;client=null;}
    record Identity(String symbol,int securityId,long instrumentId,String isin,String snapshotId,String snapshotDate,
                    String providerSha256,String constituentSha256){
        Map<String,Object> evidence(){return Map.ofEntries(
            Map.entry("symbol",symbol),Map.entry("securityId",securityId),Map.entry("instrumentId",instrumentId),Map.entry("isin",isin),
            Map.entry("snapshotId",snapshotId),Map.entry("snapshotDate",snapshotDate),Map.entry("providerSha256",providerSha256),
            Map.entry("constituentSha256",constituentSha256),Map.entry("basis","UNIQUE_NSE_EQ_SYMBOL_BRIDGE"),
            Map.entry("membershipScope","LATEST_PUBLISHED_FILE"),Map.entry("providerIsinVerified",false));}
    }
    Identity resolve(String symbol,Map<String,Object> local){
        if(symbol==null || !symbol.matches("[A-Z0-9][A-Z0-9&-]{0,29}"))throw new IllegalArgumentException("PAYTM_IDENTITY_SYMBOL_INVALID");
        if(!Boolean.TRUE.equals(local.get("snapshotMatched")) || !symbol.equals(local.get("symbol")))throw new IllegalStateException("PAYTM_IDENTITY_LOCAL_MISMATCH");
        try{
            byte[] provider=source.read(PAYTM),constituents=source.read(NIFTY);
            String csv=decode(provider);var lines=csv.lines().filter(l->!l.isBlank()).toList();
            if(lines.size()<2 || lines.size()>30001)throw new IllegalArgumentException();
            var header=fields(lines.getFirst());
            if(new HashSet<>(header).size()!=header.size())throw new IllegalArgumentException();
            for(String field:List.of("symbol","security_id","exchange","series","segment","instrument_type"))if(!header.contains(field))throw new IllegalArgumentException();
            List<List<String>> rows=new ArrayList<>();
            for(String line:lines.subList(1,lines.size())){var row=fields(line);if(row.size()!=header.size())throw new IllegalArgumentException();rows.add(row);}
            int sym=header.indexOf("symbol"),id=header.indexOf("security_id"),ex=header.indexOf("exchange"),series=header.indexOf("series"),seg=header.indexOf("segment"),type=header.indexOf("instrument_type");
            var matches=rows.stream().filter(r->symbol.equals(r.get(sym)) && "NSE".equals(r.get(ex)) && "EQ".equals(r.get(series)) && "E".equals(r.get(seg)) && "ES".equals(r.get(type))).toList();
            if(matches.size()!=1 || !matches.getFirst().get(id).matches("[1-9][0-9]{0,7}"))throw new IllegalArgumentException();
            String securityId=matches.getFirst().get(id);
            if(rows.stream().filter(r->"NSE".equals(r.get(ex)) && r.get(id).matches("[0-9]{1,8}") && Long.parseLong(securityId)==Long.parseLong(r.get(id))).count()!=1)throw new IllegalArgumentException();
            var members=new CurrentNifty500CsvParser().parse(new StringReader(decode(constituents)));
            var selected=members.stream().filter(m->symbol.equals(m.symbol()) && "EQ".equals(m.series())).toList();
            if(selected.size()!=1 || !selected.getFirst().isin().matches("[A-Z]{2}[A-Z0-9]{9}[0-9]") || !selected.getFirst().isin().equals(local.get("isin")))throw new IllegalArgumentException();
            long instrumentId=((Number)local.get("instrumentId")).longValue();if(instrumentId<=0)throw new IllegalArgumentException();
            return new Identity(symbol,Integer.parseInt(securityId),instrumentId,selected.getFirst().isin(),
                UUID.fromString((String)local.get("snapshotId")).toString(),java.time.LocalDate.parse((String)local.get("observedOn")).toString(),hash(provider),hash(constituents));
        }catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();throw new IllegalStateException("PAYTM_IDENTITY_SOURCE_OR_MATCH_FAILED");}
    }
    private static String decode(byte[] bytes)throws Exception{
        if(bytes==null || bytes.length==0 || bytes.length>4194304)throw new IllegalArgumentException();
        return StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString().replaceFirst("^\uFEFF","");
    }
    private static String hash(byte[] b)throws Exception{return HexFormat.of().withUpperCase().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}
    static List<String> fields(String line){
        var result=new ArrayList<String>();var value=new StringBuilder();boolean quoted=false,closed=false;
        for(int i=0;i<line.length();i++){
            char c=line.charAt(i);
            if(c=='"'){
                if(quoted && i+1<line.length() && line.charAt(i+1)=='"'){value.append('"');i++;}
                else if(quoted){quoted=false;closed=true;}
                else if(value.isEmpty() && !closed){quoted=true;}else throw new IllegalArgumentException();
            }else if(c==',' && !quoted){result.add(value.toString());value.setLength(0);closed=false;}
            else{if(closed)throw new IllegalArgumentException();value.append(c);}
        }
        if(quoted)throw new IllegalArgumentException();result.add(value.toString());return result;
    }
    public void close(){if(client!=null)client.shutdownNow();}
}
