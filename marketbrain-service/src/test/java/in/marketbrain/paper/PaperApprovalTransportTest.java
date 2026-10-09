package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.net.*;
import java.net.http.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.Flow;
import static org.junit.jupiter.api.Assertions.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperApprovalVerification.proposal;
import static in.marketbrain.paper.PaperApprovalHttp.*;

class PaperApprovalTransportTest {
    static final Clock CLOCK=Clock.fixed(T,ZoneOffset.UTC);
    static final Proposal PROPOSAL=proposal("http",Side.BUY,1,0);
    static final String KEY="NSE_EQ|INE123A01016";
    static String body(){return "{\"status\":\"success\",\"data\":{\"NSE_EQ:FIXTURE\":{\"instrument_token\":\""+KEY+"\",\"symbol\":\"FIXTURE\",\"last_price\":100.00,\"timestamp\":\""+T+"\",\"last_trade_time\":\""+T.toEpochMilli()+"\"}}}";}
    static Response response(String body){return new Response(200,body.getBytes(StandardCharsets.UTF_8));}
    @Test void exactIdentityTimeAndPaise()throws Exception{AtomicReference<HttpRequest> request=new AtomicReference<>();var source=upstox(r->{request.set(r);return response(body());},p->KEY,()->"fixture-only",CLOCK);var q=source.latest(PROPOSAL);assertEquals("UPSTOX",q.provider());assertEquals(10000,q.pricePaise());assertEquals(T,q.observedAt());assertEquals(DEADLINE,request.get().timeout().orElseThrow());assertEquals("GET",request.get().method());assertTrue(request.get().uri().toString().contains("NSE_EQ%7C"));}
    @ParameterizedTest @ValueSource(strings={"missingKey","wrongKey","wrongSymbol","failedStatus","missingTimestamp","missingTrade","futureTrade","futurePublished","zeroPrice","fractionalPrice","multipleQuotes","malformed"})
    void invalidProviderPayload(String kind){String b=body();switch(kind){
        case "missingKey"->b=b.replace("instrument_token","absent");case "wrongKey"->b=b.replace(KEY,"NSE_EQ|INE999A01016");case "wrongSymbol"->b=b.replace("FIXTURE","OTHER");
        case "failedStatus"->b=b.replace("success","error");case "missingTimestamp"->b=b.replace("timestamp","missing");case "missingTrade"->b=b.replace("last_trade_time","missing");
        case "futureTrade"->b=b.replace(Long.toString(T.toEpochMilli()),Long.toString(T.plusSeconds(1).toEpochMilli()));case "futurePublished"->b=b.replace(T.toString(),T.plusSeconds(1).toString());
        case "zeroPrice"->b=b.replace("100.00","0");case "fractionalPrice"->b=b.replace("100.00","100.005");case "multipleQuotes"->b=b.replace("\"data\":{","\"data\":{\"OTHER\":{},");case "malformed"->b="bad";}
        String payload=b;assertThrows(SafeFailure.class,()->upstox(r->response(payload),p->KEY,()->"fixture",CLOCK).latest(PROPOSAL));}
    @Test void providerFloatNoiseToleratedOnlyAtPaise()throws Exception{assertEquals(5205,upstox(r->response(body().replace("100.00","52.04999923706055")),p->KEY,()->"fixture",CLOCK).latest(PROPOSAL).pricePaise());}
    @Test void oldTradeNotRejuvenatedByNewSnapshot()throws Exception{String b=body().replace(Long.toString(T.toEpochMilli()),Long.toString(T.minusSeconds(60).toEpochMilli()));assertEquals(T.minusSeconds(60),upstox(r->response(b),p->KEY,()->"fixture",CLOCK).latest(PROPOSAL).observedAt());}
    @Test void noFallbackOrRetryOn429(){AtomicInteger calls=new AtomicInteger();assertThrows(SafeFailure.class,()->upstox(r->{calls.incrementAndGet();return new Response(429,new byte[0]);},p->KEY,()->"fixture",CLOCK).latest(PROPOSAL));assertEquals(1,calls.get());}
    @Test void malformedKeyPreventsRequest(){assertThrows(SafeFailure.class,()->upstox(r->{fail("Network called");return null;},p->"other,extra",()->"fixture",CLOCK).latest(PROPOSAL));}
    @Test void errorsNeverExposeProviderCredentials(){var e=assertThrows(SafeFailure.class,()->upstox(r->{throw new IllegalStateException("secret-fixture");},p->KEY,()->"fixture",CLOCK).latest(PROPOSAL));assertFalse(e.toString().contains("secret-fixture"));assertNull(e.getCause());}
    @Test void oversizedPayloadRejected(){assertThrows(SafeFailure.class,()->upstox(r->new Response(200,new byte[BODY_LIMIT+1]),p->KEY,()->"fixture",CLOCK).latest(PROPOSAL));}
    @Test void telegramTemplateAndSuccessfulAcknowledgement()throws Exception{var tokens=new Tokens("a".repeat(43),"b".repeat(43));var message=message(PROPOSAL,tokens);String json=JSON.writeValueAsString(message);assertTrue(json.contains("NO EXECUTION"));assertTrue(json.contains("mbp:"+tokens.accept()));assertTrue(json.contains("protect_content"));assertEquals(47,("mbp:"+tokens.accept()).length());assertEquals("12",telegram(r->response("{\"ok\":true,\"result\":{\"message_id\":12,\"chat\":{\"id\":222,\"type\":\"private\"}}}"),()->"123:fixture_only_token",CLOCK).send(PROPOSAL,tokens));}
    @ParameterizedTest @ValueSource(strings={"{\"ok\":false}","{\"ok\":true}","{\"ok\":true,\"result\":{\"message_id\":12,\"chat\":{\"id\":999,\"type\":\"private\"}}}"})
    void ambiguousTelegramAcknowledgementRejected(String body){assertThrows(SafeFailure.class,()->telegram(r->response(body),()->"123:fixture_only_token",CLOCK).send(PROPOSAL,new Tokens("a".repeat(43),"b".repeat(43))));}
    @Test void expiredProposalNeverSent(){assertThrows(SafeFailure.class,()->telegram(r->{fail("Send called");return null;},()->"123:fixture_only_token",Clock.fixed(T.plusSeconds(120),ZoneOffset.UTC)).send(PROPOSAL,new Tokens("a".repeat(43),"b".repeat(43))));}
    @Test void encryptedDeliveryIsBoundToKeyAndProposal(){byte[] key=new byte[32];Arrays.fill(key,(byte)7);var vault=new PaperApprovalDelivery.Vault(key);String sealed=vault.seal("opaque fixture tokens","p");assertFalse(sealed.contains("opaque"));assertEquals("opaque fixture tokens",vault.open(sealed,"p"));assertThrows(IllegalArgumentException.class,()->vault.open(sealed,"other"));assertThrows(IllegalArgumentException.class,()->new PaperApprovalDelivery.Vault(new byte[32]).open(sealed,"p"));assertNotEquals(sealed,vault.seal("opaque fixture tokens","p"));}
    @Test void damagedCiphertextAndMissingKeyRejected(){assertThrows(IllegalArgumentException.class,()->new PaperApprovalDelivery.Vault(new byte[16]));assertThrows(IllegalArgumentException.class,()->new PaperApprovalDelivery.Vault(new byte[32]).open("broken","p"));}
    @ParameterizedTest @ValueSource(strings={"http://api.upstox.com/v2/market-quote/quotes","https://evil.test/v2/market-quote/quotes","https://api.upstox.com/v2/order/place","https://api.upstox.com:443/v2/market-quote/quotes","https://x@api.upstox.com/v2/market-quote/quotes"})
    void onlyPinnedReviewPaths(String uri){assertFalse(allowed(URI.create(uri)));}
    @Test void boundedSubscriberCancelsOversizedResponse(){var subscriber=new LimitedBody(4);AtomicBoolean cancelled=new AtomicBoolean();subscriber.onSubscribe(new Flow.Subscription(){public void request(long n){}public void cancel(){cancelled.set(true);}});subscriber.onNext(List.of(ByteBuffer.wrap(new byte[5])));assertTrue(cancelled.get());assertThrows(CompletionException.class,()->subscriber.getBody().toCompletableFuture().join());}
    @Test void boundedSubscriberAcceptsSmallBody(){var subscriber=new LimitedBody(4);subscriber.onSubscribe(new Flow.Subscription(){public void request(long n){}public void cancel(){}});subscriber.onNext(List.of(ByteBuffer.wrap(new byte[]{1,2})));subscriber.onComplete();assertArrayEquals(new byte[]{1,2},subscriber.getBody().toCompletableFuture().join());}
    @Test @SuppressWarnings("unchecked") void hardDeadlineCancelsUnfinishedHttpFuture(){
        var client=org.mockito.Mockito.mock(HttpClient.class);var pending=new CompletableFuture<HttpResponse<byte[]>>();
        org.mockito.Mockito.doReturn(pending).when(client).sendAsync(org.mockito.ArgumentMatchers.any(HttpRequest.class),org.mockito.ArgumentMatchers.any(HttpResponse.BodyHandler.class));
        var transport=new BoundedTransport(client);
        assertThrows(SafeFailure.class,()->transport.exchange(HttpRequest.newBuilder(URI.create("https://api.upstox.com/v2/market-quote/quotes")).GET().build()));
        assertTrue(pending.isCancelled());
    }
}
