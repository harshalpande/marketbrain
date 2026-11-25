import java.nio.file.*;
import java.net.*;
import java.time.*;
import java.util.*;
import java.util.jar.*;
import java.lang.reflect.*;
import java.security.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import javax.net.ssl.*;

/** Isolated synthetic inputs against the copied deployed assessor; no application boot or networking. */
public final class DeployedQuoteQualityProbe {
    static final class FixtureHttp extends HttpClient {
        String body;int calls;
        public Optional<java.net.CookieHandler> cookieHandler(){return Optional.empty();}
        public Optional<Duration> connectTimeout(){return Optional.empty();}
        public Redirect followRedirects(){return Redirect.NEVER;}
        public Optional<ProxySelector> proxy(){return Optional.empty();}
        public SSLContext sslContext(){try{return SSLContext.getDefault();}catch(Exception e){throw new IllegalStateException(e);}}
        public SSLParameters sslParameters(){return new SSLParameters();}
        public Optional<Authenticator> authenticator(){return Optional.empty();}
        public Version version(){return Version.HTTP_1_1;}
        public Optional<Executor> executor(){return Optional.empty();}
        public <T> HttpResponse<T> send(HttpRequest request,HttpResponse.BodyHandler<T> handler){
            calls++;
            if(!request.uri().toString().equals("https://developer.paytmmoney.com/data/v1/price/live?mode=LTP&pref=NSE:2885:EQUITY")||!request.method().equals("GET")||!request.headers().firstValue("x-jwt-token").orElse("").equals("fixture-read-only"))throw new IllegalStateException("REQUEST_SCOPE_FAILED");
            var headers=HttpHeaders.of(Map.of(),(a,b)->true);
            var info=new HttpResponse.ResponseInfo(){public int statusCode(){return 200;}public HttpHeaders headers(){return headers;}public Version version(){return Version.HTTP_1_1;}};
            var sub=handler.apply(info);
            sub.onSubscribe(new Flow.Subscription(){public void request(long n){}public void cancel(){}});
            sub.onNext(List.of(ByteBuffer.wrap(body.getBytes(StandardCharsets.UTF_8))));sub.onComplete();
            T value=sub.getBody().toCompletableFuture().join();
            return new HttpResponse<T>(){
                public int statusCode(){return 200;}public HttpRequest request(){return request;}public Optional<HttpResponse<T>> previousResponse(){return Optional.empty();}
                public HttpHeaders headers(){return headers;}public T body(){return value;}public Optional<SSLSession> sslSession(){return Optional.of(sslContext().createSSLEngine().getSession());}
                public URI uri(){return request.uri();}public Version version(){return Version.HTTP_1_1;}
            };
        }
        public <T> CompletableFuture<HttpResponse<T>> sendAsync(HttpRequest r,HttpResponse.BodyHandler<T> h){throw new UnsupportedOperationException();}
        public <T> CompletableFuture<HttpResponse<T>> sendAsync(HttpRequest r,HttpResponse.BodyHandler<T> h,HttpResponse.PushPromiseHandler<T> p){throw new UnsupportedOperationException();}
        public void shutdownNow(){}
    }
    record Case(String name, String body, String expected, boolean fresh) {}
    static final Instant NOW=Instant.parse("2026-11-25T04:00:00Z");
    static final long RAW=NOW.getEpochSecond()-315532800L;
    static String row(String id,String mode,String found,String price,String time) {
        return "{\"security_id\":"+id+",\"mode\":\""+mode+"\",\"found\":"+found+",\"last_price\":"+price+",\"last_trade_time\":"+time+"}";
    }
    static String body(String row){return "{\"data\":["+row+"]}";}
    static Case c(String name,String row,String status){return new Case(name,body(row),status,false);}
    static List<Case> cases(){
        String good=row("2885","LTP","true","100",Long.toString(RAW));
        return List.of(
            new Case("fresh",body(good),"FRESH_QUOTE_OBSERVED",true),
            new Case("exact15Seconds",body(row("2885","LTP","true","100",Long.toString(RAW-15))),"FRESH_QUOTE_OBSERVED",true),
            c("stale",row("2885","LTP","true","100",Long.toString(RAW-16)),"STALE_QUOTE"),
            c("future",row("2885","LTP","true","100",Long.toString(RAW+1)),"FUTURE_TIMESTAMP"),
            c("notFound",row("2885","LTP","false","100",Long.toString(RAW)),"NO_QUOTE"),
            c("wrongId",row("1","LTP","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("textId",row("\"2885\"","LTP","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("wrongMode",row("2885","FULL","true","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("textFound",row("2885","LTP","\"true\"","100",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("missingPrice",good.replace(",\"last_price\":100",""),"MALFORMED_QUOTE"),
            c("textPrice",row("2885","LTP","true","\"100\"",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("zeroPrice",row("2885","LTP","true","0",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("negativePrice",row("2885","LTP","true","-1",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("excessivePrice",row("2885","LTP","true","1000000001",Long.toString(RAW)),"MALFORMED_QUOTE"),
            c("missingTime",good.replace(",\"last_trade_time\":"+RAW,""),"MISSING_OR_INVALID_TIMESTAMP"),
            c("textTime",row("2885","LTP","true","100","\""+RAW+"\""),"MISSING_OR_INVALID_TIMESTAMP"),
            c("millisecondsTime",row("2885","LTP","true","100",Long.toString(NOW.toEpochMilli())),"MISSING_OR_INVALID_TIMESTAMP"),
            c("overflowTime",row("2885","LTP","true","100","99999999999999999999999"),"MISSING_OR_INVALID_TIMESTAMP"),
            new Case("duplicate",body(good+","+good),"MALFORMED_QUOTE",false),
            new Case("emptyData","{\"data\":[]}","MALFORMED_QUOTE",false),
            new Case("missingData","{}","MALFORMED_QUOTE",false),
            new Case("providerError","{\"error\":\"fixture\",\"data\":["+good+"]}","MALFORMED_QUOTE",false),
            new Case("nullReply","null","MALFORMED_QUOTE",false),
            new Case("arrayReply","[]","MALFORMED_QUOTE",false));
    }
    public static void main(String[] args)throws Exception{
        Path artifact=Path.of(args[0]), dir=Files.createTempDirectory(artifact.getParent(),"quality-classes-");
        String entry="BOOT-INF/classes/in/marketbrain/marketdata/paytm/PaytmQuoteProbe.class";
        String classHash=null;List<URL> urls=new ArrayList<>();urls.add(dir.toUri().toURL());int libraries=0;
        try{
            try(JarFile jar=new JarFile(artifact.toFile())){
                var all=jar.entries();
                while(all.hasMoreElements()){
                    var e=all.nextElement();String name=e.getName();
                    boolean assessor=name.equals(entry), client=name.matches("BOOT-INF/classes/in/marketbrain/marketdata/paytm/PaytmSupervisedClient(\\$[A-Za-z0-9]+)?\\.class"), lib=name.matches("BOOT-INF/lib/jackson-(core|databind|annotations)-[0-9][A-Za-z0-9._-]*\\.jar");
                    if(!assessor&&!client&&!lib)continue;
                    if(e.getSize()<1||e.getSize()>8_000_000)throw new IllegalStateException("ENTRY_SIZE_REJECTED");
                    byte[] bytes;try(var in=jar.getInputStream(e)){bytes=in.readNBytes(8_000_001);}
                    if(bytes.length!=e.getSize())throw new IllegalStateException("ENTRY_READ_REJECTED");
                    Path target=dir.resolve((assessor||client)?name.substring("BOOT-INF/classes/".length()):Path.of(name).getFileName().toString());
                    Files.createDirectories(target.getParent());Files.write(target,bytes,StandardOpenOption.CREATE_NEW);
                    if(assessor)classHash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
                    else if(lib){urls.add(target.toUri().toURL());libraries++;}
                }
            }
            if(classHash==null||libraries!=3)throw new IllegalStateException("ARTIFACT_COMPONENTS_MISSING");
            try(var loader=new URLClassLoader(urls.toArray(URL[]::new),ClassLoader.getPlatformClassLoader())){
                Class<?> mapperClass=loader.loadClass("com.fasterxml.jackson.databind.ObjectMapper");
                Object mapper=mapperClass.getConstructor().newInstance();Method parse=mapperClass.getMethod("readTree",String.class);
                var http=new FixtureHttp();var clientClass=loader.loadClass("in.marketbrain.marketdata.paytm.PaytmSupervisedClient");
                var ctor=clientClass.getDeclaredConstructor(HttpClient.class);ctor.setAccessible(true);Object client=ctor.newInstance(http);
                var quote=clientClass.getDeclaredMethod("quote",String.class,int.class);quote.setAccessible(true);
                Method assess=loader.loadClass("in.marketbrain.marketdata.paytm.PaytmQuoteProbe").getDeclaredMethod("assess",loader.loadClass("com.fasterxml.jackson.databind.JsonNode"),int.class,Instant.class);assess.setAccessible(true);
                List<Map<String,Object>> checks=new ArrayList<>();
                for(Case c:cases()){
                    http.body=c.body();
                    Map<?,?> result=(Map<?,?>)assess.invoke(null,quote.invoke(client,"fixture-read-only",2885),2885,NOW);
                    boolean ok=c.expected().equals(result.get("status"))&&Boolean.valueOf(c.fresh()).equals(result.get("fresh"))&&Boolean.FALSE.equals(result.get("ordersEnabled"))&&Boolean.FALSE.equals(result.get("mappingVerified"));
                    checks.add(Map.of("name",c.name(),"passed",ok,"expected",c.expected(),"actual",String.valueOf(result.get("status"))));
                }
                http.body="invalid-json";boolean rejected=false;
                try{quote.invoke(client,"fixture-read-only",2885);}catch(InvocationTargetException e){rejected="PAYTM_TRANSPORT_OR_JSON_FAILED".equals(e.getCause().getMessage());}
                checks.add(Map.of("name","invalidJson","passed",rejected,"expected","PAYTM_TRANSPORT_OR_JSON_FAILED","actual",rejected?"PAYTM_TRANSPORT_OR_JSON_FAILED":"UNEXPECTED"));
                boolean passed=checks.stream().allMatch(c->Boolean.TRUE.equals(c.get("passed")))&&http.calls==25;
                clientClass.getMethod("close").invoke(client);
                System.out.println(mapperClass.getMethod("writeValueAsString",Object.class).invoke(mapper,Map.of("passed",passed,"checks",checks,"assessorSha256",classHash,"scope","COPIED_DEPLOYED_CLIENT_ASSESSOR_SIMULATED_HTTP_NATIVE_JVM","ordersEnabled",false,"networkCalls",0,"simulatedHttpCalls",http.calls)));
                if(!passed)throw new IllegalStateException("QUALITY_ASSERTION_FAILED");
            }
        }finally{
            try(var files=Files.walk(dir)){for(Path p:files.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}
        }
    }
}
