package in.marketbrain.marketdata.paytm;

import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import javax.net.ssl.SSLSession;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Production client/session chain, mocked network only; never calls the provider. */
class PaytmQuoteRecoveryTest {
    @ParameterizedTest @ValueSource(ints={401,429,503,0})
    @SuppressWarnings("unchecked")
    void errorLocksSessionWithoutRetryAndFreshLoginRestoresRead(int failureCode)throws Exception{
        HttpClient http=mock(HttpClient.class);AtomicInteger sends=new AtomicInteger();
        when(http.send(any(HttpRequest.class),any(HttpResponse.BodyHandler.class))).thenAnswer(invocation->{
            int n=sends.incrementAndGet();
            HttpRequest request=invocation.getArgument(0);
            assertThat(request.uri().getHost()).isEqualTo("developer.paytmmoney.com");
            assertThat(request.timeout()).contains(java.time.Duration.ofSeconds(15));
            if(n==3 && failureCode==0)throw new HttpTimeoutException("PRIVATE_TRANSPORT_DETAIL");
            HttpResponse<byte[]> reply=mock(HttpResponse.class);
            when(reply.sslSession()).thenReturn(Optional.of(mock(SSLSession.class)));
            when(reply.statusCode()).thenReturn(n==3?failureCode:200);
            String body;
            if(n==1 || n==4){
                assertThat(request.method()).isEqualTo("POST");
                body="{\"read_access_token\":\"read-"+n+"\",\"access_token\":\"trade-never-used\"}";
            }else{
                assertThat(request.method()).isEqualTo("GET");
                assertThat(request.headers().firstValue("x-jwt-token")).contains(n<4?"read-1":"read-4");
                body=(n==2 || n==5)?"{\"status\":\"success\"}":(n==3?"PRIVATE_PROVIDER_DETAIL":PaytmQuoteProbeTest.reply(0).toString());
            }
            when(reply.body()).thenReturn(body.getBytes(StandardCharsets.UTF_8));return reply;
        });
        try(var client=new PaytmSupervisedClient(http);var session=new PaytmSupervisedSession(client)){
            login(session);
            String expected=failureCode==0?"PAYTM_TRANSPORT_OR_JSON_FAILED":"PAYTM_HTTP_"+failureCode;
            assertThatThrownBy(()->session.quote(3456)).hasMessage(expected);
            assertThat(session.status()).containsEntry("status","LOCKED").containsEntry("readAccessVerified",false);
            assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_LOCKED");
            assertThat(sends.get()).isEqualTo(3); // no retry or fallback after rejection
            login(session);
            assertThat(session.quote(3456)).containsEntry("fresh",true).containsEntry("ordersEnabled",false);
            assertThat(sends.get()).isEqualTo(6);
            assertThat(session.status().toString()).doesNotContain("PRIVATE_","trade-never-used","read-1","read-4");
        }
    }
    private void login(PaytmSupervisedSession session){
        String url=session.start("key","secret",PaytmQuoteProbeTest.NOW.toEpochMilli());
        var browser=session.browser(URI.create(url).getQuery().substring(5));
        String state=browser.location().getQuery().split("state=")[1];
        session.completeCallback("success=true&state="+state+"&requestToken=fixture",browser.binding());
    }
}
