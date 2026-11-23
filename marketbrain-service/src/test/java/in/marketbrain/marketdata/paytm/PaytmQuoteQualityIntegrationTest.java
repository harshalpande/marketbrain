package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.node.ObjectNode;
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

/** Real client parsing, session and quote assessment; only HTTP responses are simulated. */
class PaytmQuoteQualityIntegrationTest {
    @ParameterizedTest
    @ValueSource(strings={"stale","future","notFound","wrongId","wrongMode","duplicate",
        "missingPrice","negativePrice","textPrice","missingTime","millisTime","error","invalidJson","emptyBody"})
    @SuppressWarnings("unchecked")
    void unusableProviderDataNeverBecomesFreshOrTriggersFallback(String defect)throws Exception {
        var root=PaytmQuoteProbeTest.reply(defect.equals("stale")?60000:defect.equals("future")?-60000:0);
        var row=(ObjectNode)root.path("data").get(0);
        String expected=switch(defect){
            case "stale" -> "STALE_QUOTE";
            case "future" -> "FUTURE_TIMESTAMP";
            case "notFound" -> "NO_QUOTE";
            case "missingTime","millisTime" -> "MISSING_OR_INVALID_TIMESTAMP";
            default -> "MALFORMED_QUOTE";
        };
        switch(defect){
            case "notFound" -> row.put("found",false);
            case "wrongId" -> row.put("security_id",1);
            case "wrongMode" -> row.put("mode","CAS");
            case "duplicate" -> ((com.fasterxml.jackson.databind.node.ArrayNode)root.path("data")).add(row.deepCopy());
            case "missingPrice" -> row.remove("last_price");
            case "negativePrice" -> row.put("last_price",-1);
            case "textPrice" -> row.put("last_price","423.75");
            case "missingTime" -> row.remove("last_trade_time");
            case "millisTime" -> row.put("last_trade_time",PaytmQuoteProbeTest.NOW.toEpochMilli());
            case "error" -> root.put("error_code","PRIVATE_PROVIDER_DETAIL");
        }
        HttpClient http=mock(HttpClient.class);AtomicInteger sends=new AtomicInteger();
        when(http.send(any(HttpRequest.class),any(HttpResponse.BodyHandler.class))).thenAnswer(invocation->{
            int n=sends.incrementAndGet();HttpRequest request=invocation.getArgument(0);
            assertThat(n).isLessThanOrEqualTo(3);
            assertThat(request.uri().getHost()).isEqualTo("developer.paytmmoney.com");
            if(n>1)assertThat(request.headers().firstValue("x-jwt-token")).contains("read-fixture");
            if(n==3){
                assertThat(request.method()).isEqualTo("GET");
                assertThat(request.uri().getRawPath()).isEqualTo("/data/v1/price/live");
                assertThat(request.uri().getRawQuery()).isEqualTo("mode=LTP&pref=NSE:3456:EQUITY");
            }
            String body=n==1?"{\"read_access_token\":\"read-fixture\",\"access_token\":\"trade-unused\"}":
                n==2?"{\"status\":\"success\"}":defect.equals("invalidJson")?"PRIVATE_INVALID_JSON":defect.equals("emptyBody")?"":root.toString();
            HttpResponse<byte[]> reply=mock(HttpResponse.class);
            when(reply.statusCode()).thenReturn(200);when(reply.sslSession()).thenReturn(Optional.of(mock(SSLSession.class)));
            when(reply.body()).thenReturn(body.getBytes(StandardCharsets.UTF_8));return reply;
        });
        try(var client=new PaytmSupervisedClient(http);var session=new PaytmSupervisedSession(client)){
            String url=session.start("key","secret",PaytmQuoteProbeTest.NOW.toEpochMilli());
            var browser=session.browser(URI.create(url).getQuery().substring(5));
            String state=browser.location().getQuery().split("state=")[1];
            session.completeCallback("success=true&state="+state+"&requestToken=fixture",browser.binding());
            if(defect.equals("invalidJson")){
                assertThatThrownBy(()->session.quote(3456)).hasMessage("PAYTM_TRANSPORT_OR_JSON_FAILED");
                assertThat(session.status()).containsEntry("status","LOCKED");
            }else{
                var result=session.quote(3456);
                assertThat(result).containsEntry("status",expected).containsEntry("fresh",false)
                    .containsEntry("ordersEnabled",false).containsEntry("mappingVerified",false)
                    .containsEntry("securityId",3456);
                assertThat(result.toString()).doesNotContain("PRIVATE_","read-fixture","trade-unused");
            }
            assertThat(sends.get()).isEqualTo(3);
            session.close();
            assertThatThrownBy(()->session.quote(3456)).hasMessage("SUPERVISED_SESSION_LOCKED");
            assertThat(sends.get()).isEqualTo(3);
        }
    }
}
