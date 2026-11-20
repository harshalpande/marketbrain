package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import java.net.http.*;
import java.util.Optional;
import javax.net.ssl.SSLSession;

class PaytmSupervisedClientTest {
    @SuppressWarnings("unchecked")
    private PaytmSupervisedClient client(int code, String body, boolean tls) throws Exception {
        HttpClient http=mock(HttpClient.class);
        HttpResponse<byte[]> response=mock(HttpResponse.class);
        when(response.statusCode()).thenReturn(code);
        when(response.body()).thenReturn(body.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        when(response.sslSession()).thenReturn(tls?Optional.of(mock(SSLSession.class)):Optional.empty());
        when(http.send(any(HttpRequest.class),any(HttpResponse.BodyHandler.class))).thenReturn(response);
        return new PaytmSupervisedClient(http);
    }
    @Test void retainsOnlyReadTokenAndRejectsTradingTokenFallback() throws Exception {
        assertThat(client(200,"{\"access_token\":\"trade\",\"read_access_token\":\"read\"}",true).exchange("key","secret","request")).isEqualTo("read");
        var tradeOnly=client(200,"{\"access_token\":\"trade\"}",true);
        assertThatThrownBy(()->tradeOnly.exchange("key","secret","request")).hasMessage("PAYTM_READ_TOKEN_MISSING");
    }
    @Test void rejectsRedirectUnauthorizedMalformedAndNoTlsWithoutReturningBodies() throws Exception {
        for(int status:new int[]{302,401,403,429,503}) {
            var c=client(status,"private account or error content",true);
            assertThatThrownBy(()->c.exchange("key","secret","request")).hasMessage("PAYTM_HTTP_"+status);
        }
        var malformed=client(200,"not json",true);
        assertThatThrownBy(()->malformed.exchange("key","secret","request")).hasMessage("PAYTM_TRANSPORT_OR_JSON_FAILED");
        var clear=client(200,"{}",false);
        assertThatThrownBy(()->clear.exchange("key","secret","request")).hasMessage("PAYTM_RESPONSE_REJECTED");
    }
    @Test void rejectsErrorObjectsEvenWithHttp200() throws Exception {
        for(String body:new String[]{"{}","[]","{\"error\":\"private\"}","{\"success\":false}","{\"status\":\"error\"}"}) {
            var c=client(200,body,true);
            assertThatThrownBy(()->c.verifyRead("read")).hasMessage("PAYTM_ACCOUNT_READ_REJECTED");
        }
    }
}
