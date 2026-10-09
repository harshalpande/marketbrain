package in.marketbrain.paper;

import com.fasterxml.jackson.databind.*;
import java.math.*;
import java.net.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.Flow;
import java.util.function.Supplier;
import static in.marketbrain.paper.PaperApprovalReview.*;

/** Explicitly constructed adapters only. No model, database write, order endpoint or retry. */
public final class PaperApprovalHttp {
    static final ObjectMapper JSON=new ObjectMapper().enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
    static final Duration DEADLINE=Duration.ofSeconds(3);
    static final int BODY_LIMIT=32768;
    public record Response(int status,byte[] body) {}
    @FunctionalInterface public interface Transport { Response exchange(HttpRequest request)throws Exception; }
    @FunctionalInterface public interface InstrumentKeys { String resolve(Proposal proposal)throws Exception; }
    public static InstrumentKeys jdbcInstrumentKeys(PaperLedgerStore.Connections connections){
        return proposal->{try(var c=connections.open()){
            c.setReadOnly(true);
            try(var s=PaperLedgerStore.statement(c,"SELECT pi.provider_instrument_key FROM provider_instrument pi JOIN market_data_source s ON s.id=pi.source_id JOIN instrument i ON i.id=pi.instrument_id WHERE s.code='UPSTOX' AND s.enabled=TRUE AND pi.instrument_id=? AND pi.active=TRUE AND i.active=TRUE AND i.symbol=? AND pi.segment='NSE_EQ' AND pi.instrument_type='EQ' LIMIT 2",proposal.instrumentId(),proposal.terms().symbol());var r=s.executeQuery()){
                if(!r.next())throw new SafeFailure();String key=r.getString(1);if(r.next())throw new SafeFailure();return key;
            }
        }};
    }
    public static final class SafeFailure extends Exception {public SafeFailure(){super("Review transport unavailable; provider details withheld");}}

    /** Single caller-owned client. Future deadline includes response-body completion; no redirects. */
    public static final class BoundedTransport implements Transport,AutoCloseable {
        private final HttpClient client;
        public BoundedTransport(){this(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).followRedirects(HttpClient.Redirect.NEVER).build());}
        BoundedTransport(HttpClient client){this.client=Objects.requireNonNull(client);}
        public Response exchange(HttpRequest request)throws Exception{
            if(!allowed(request.uri()))throw new SafeFailure();
            var future=client.sendAsync(request,info->new LimitedBody(BODY_LIMIT));
            try{var response=future.get(DEADLINE.toMillis(),TimeUnit.MILLISECONDS);return new Response(response.statusCode(),response.body());}
            catch(InterruptedException interrupted){future.cancel(true);Thread.currentThread().interrupt();throw interrupted;}
            catch(Exception failure){future.cancel(true);throw new SafeFailure();}
        }
        public void close(){client.shutdownNow();}
    }
    static boolean allowed(URI uri){return "https".equals(uri.getScheme())&&uri.getPort()==-1&&uri.getUserInfo()==null&&uri.getFragment()==null&&
            (("api.upstox.com".equals(uri.getHost())&&"/v2/market-quote/quotes".equals(uri.getPath()))||
             ("api.telegram.org".equals(uri.getHost())&&uri.getPath().matches("/bot[0-9]+:[A-Za-z0-9_-]+/sendMessage")&&uri.getQuery()==null));}
    static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
        private final HttpResponse.BodySubscriber<byte[]> delegate=HttpResponse.BodySubscribers.ofByteArray();
        private final int limit;private long size;private Flow.Subscription subscription;private boolean ended;
        LimitedBody(int limit){this.limit=limit;}
        public CompletionStage<byte[]> getBody(){return delegate.getBody();}
        public void onSubscribe(Flow.Subscription subscription){this.subscription=subscription;delegate.onSubscribe(subscription);}
        public void onNext(List<ByteBuffer> buffers){if(ended)return;for(var b:buffers)size+=b.remaining();if(size>limit){ended=true;subscription.cancel();delegate.onError(new IllegalStateException("Response exceeds review bound"));}else delegate.onNext(buffers);}
        public void onError(Throwable error){if(!ended){ended=true;delegate.onError(new IllegalStateException("Review response unavailable"));}}
        public void onComplete(){if(!ended){ended=true;delegate.onComplete();}}
    }
    public static QuoteSource upstox(Transport transport,InstrumentKeys keys,Supplier<String> credential,Clock clock){
        Objects.requireNonNull(transport);Objects.requireNonNull(keys);Objects.requireNonNull(credential);Objects.requireNonNull(clock);
        return proposal->{
            try{
                String key=keys.resolve(proposal);if(key==null||!key.matches("NSE_EQ\\|INE[A-Z0-9]{9}"))throw new SafeFailure();
                String token=credential.get();if(token==null||token.isBlank()||token.length()>4096||token.contains("\r")||token.contains("\n"))throw new SafeFailure();
                URI uri=URI.create("https://api.upstox.com/v2/market-quote/quotes?instrument_key="+URLEncoder.encode(key,StandardCharsets.UTF_8));
                HttpRequest request=HttpRequest.newBuilder(uri).timeout(DEADLINE).header("Accept","application/json").header("Authorization","Bearer "+token).GET().build();
                Response response=transport.exchange(request);Instant received=clock.instant();JsonNode json=parse(response);
                if(!"success".equals(json.path("status").asText())||!json.path("data").isObject()||json.path("data").size()!=1)throw new SafeFailure();
                JsonNode q=json.path("data").elements().next();
                if(!key.equals(q.path("instrument_token").asText())||!proposal.terms().symbol().equals(q.path("symbol").asText())||!q.path("last_price").isNumber())throw new SafeFailure();
                BigDecimal price=q.path("last_price").decimalValue(),rounded=price.setScale(2,RoundingMode.HALF_UP);
                // Only tolerate representation noise (e.g. provider 52.049999237 instead of 52.05).
                if(price.subtract(rounded).abs().compareTo(new BigDecimal("0.00001"))>0)throw new SafeFailure();
                long paise=rounded.movePointRight(2).longValueExact();if(paise<=0)throw new SafeFailure();
                Instant published=time(q.path("timestamp")),trade=time(q.path("last_trade_time"));
                if(trade.isAfter(published)||published.isAfter(received))throw new SafeFailure();
                // Last trade age governs LTP; receiving a new snapshot cannot rejuvenate an old trade.
                return new MarketQuote(proposal.instrumentId(),proposal.terms().symbol(),"UPSTOX",paise,trade,received);
            }catch(InterruptedException interrupted){throw interrupted;}catch(Exception invalid){throw new SafeFailure();}
        };
    }
    static Instant time(JsonNode value){String text=value.asText("");if(text.matches("[0-9]{13}"))return Instant.ofEpochMilli(Long.parseLong(text));return OffsetDateTime.parse(text).toInstant();}
    static JsonNode parse(Response response)throws Exception{if(response==null||response.status()!=200||response.body()==null||response.body().length>BODY_LIMIT)throw new SafeFailure();return JSON.readTree(response.body());}
    public static PaperApprovalDelivery.Sender telegram(Transport transport,Supplier<String> credential,Clock clock){
        Objects.requireNonNull(transport);Objects.requireNonNull(credential);Objects.requireNonNull(clock);
        return (proposal,tokens)->{
            try{
                if(!clock.instant().isBefore(proposal.terms().expiresAt())||clock.instant().isBefore(proposal.terms().createdAt()))throw new SafeFailure();
                String secret=credential.get();if(secret==null||!secret.matches("[0-9]{1,20}:[A-Za-z0-9_-]{10,200}"))throw new SafeFailure();
                byte[] body=JSON.writeValueAsBytes(message(proposal,tokens));
                var request=HttpRequest.newBuilder(URI.create("https://api.telegram.org/bot"+secret+"/sendMessage")).timeout(DEADLINE)
                        .header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofByteArray(body)).build();
                var json=parse(transport.exchange(request));var result=json.path("result");
                if(!json.path("ok").isBoolean()||!json.path("ok").booleanValue()||!result.path("message_id").isIntegralNumber()||result.path("message_id").asLong()<=0
                   ||!result.path("chat").path("id").isIntegralNumber()||result.path("chat").path("id").asLong()!=proposal.chatId()||!"private".equals(result.path("chat").path("type").asText()))throw new SafeFailure();
                return result.path("message_id").asText();
            }catch(InterruptedException interrupted){throw interrupted;}catch(Exception invalid){throw new SafeFailure();}
        };
    }
    static Map<String,Object> message(Proposal p,Tokens tokens){
        if(tokens==null||tokens.accept()==null||tokens.reject()==null||!tokens.accept().matches("[A-Za-z0-9_-]{43}")||!tokens.reject().matches("[A-Za-z0-9_-]{43}"))throw new IllegalArgumentException("Invalid action tokens");
        var a=p.terms();String text="[PAPER REVIEW ONLY - NO EXECUTION]\n"+a.side()+" "+a.symbol()+" | quantity "+a.quantity()+
                "\nReference INR "+rupees(a.referencePaise())+" | zone "+rupees(a.zoneMinPaise())+" - "+rupees(a.zoneMaxPaise())+
                "\nCreated "+a.createdAt()+"\nExpires "+a.expiresAt()+"\nPolicy "+p.policyId()+" | account revision "+p.expectedRevision()+
                "\nACCEPT requests fresh quote/risk review only. No cash reservation or order. Proposal "+p.id();
        return Map.of("chat_id",p.chatId(),"text",text,"protect_content",true,"reply_markup",Map.of("inline_keyboard",List.of(List.of(
                Map.of("text","ACCEPT","callback_data","mbp:"+tokens.accept()),Map.of("text","REJECT","callback_data","mbp:"+tokens.reject())))));
    }
    private static String rupees(long paise){return BigDecimal.valueOf(paise,2).toPlainString();}
}
