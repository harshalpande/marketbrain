package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.servlet.http.Cookie;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import javax.net.ssl.SSLSession;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaytmQuoteHttpIntegrationTest {
    private static final String TOKEN="a".repeat(40),BASE="/api/v1/paytm/supervised/";
    private static MockHttpServletRequestBuilder api(String command){
        return post(BASE+command).header("Host","127.0.0.1:8080")
            .header("X-MarketBrain-Paper-Read-Token",TOKEN)
            .header("X-MarketBrain-Paytm-Supervised","supervised-paper").contentType("application/json");
    }
    @ParameterizedTest @ValueSource(strings={"fresh","stale","future","missing","wrongId","invalidJson","rateLimit"})
    @SuppressWarnings("unchecked")
    void httpBoundaryUsesProviderQuoteNotCallerClaims(String defect)throws Exception{
        var provider=PaytmQuoteProbeTest.reply(defect.equals("stale")?60000:defect.equals("future")?-60000:0);
        var row=(ObjectNode)provider.path("data").get(0);
        if(defect.equals("missing"))row.put("found",false);
        if(defect.equals("wrongId"))row.put("security_id",2885);
        var sends=new AtomicInteger();HttpClient http=mock(HttpClient.class);
        when(http.send(any(HttpRequest.class),any(HttpResponse.BodyHandler.class))).thenAnswer(i->{
            int n=sends.incrementAndGet();HttpRequest request=i.getArgument(0);
            assertThat(n).isLessThanOrEqualTo(3);
            assertThat(request.uri().getHost()).isEqualTo("developer.paytmmoney.com");
            if(n>1)assertThat(request.headers().firstValue("x-jwt-token")).contains("read-fixture");
            if(n==3){assertThat(request.method()).isEqualTo("GET");assertThat(request.uri().getRawQuery()).isEqualTo("mode=LTP&pref=NSE:3456:EQUITY");}
            var reply=mock(HttpResponse.class);
            when(reply.sslSession()).thenReturn(Optional.of(mock(SSLSession.class)));
            when(reply.statusCode()).thenReturn(n==3 && defect.equals("rateLimit")?429:200);
            String body=n==1?"{\"read_access_token\":\"read-fixture\",\"access_token\":\"trade-unused\"}":n==2?"{\"status\":\"success\"}":defect.equals("invalidJson")?"PRIVATE_INVALID_BODY":provider.toString();
            when(reply.body()).thenReturn(body.getBytes(StandardCharsets.UTF_8));return reply;
        });
        var controller=new PaytmSupervisedController(TOKEN,"PAPER",false,new PaytmSupervisedClient(http));
        try{
            var mvc=MockMvcBuilders.standaloneSetup(controller).build();var json=new ObjectMapper();
            var start=mvc.perform(api("start").content("{\"apiKey\":\"fixture\",\"apiSecret\":\"fixture\",\"vpsEpochMilliseconds\":"+PaytmQuoteProbeTest.NOW.toEpochMilli()+"}"))
                .andExpect(status().isOk()).andReturn().getResponse();
            var url=URI.create(json.readTree(start.getContentAsString()).path("browserUrl").asText());
            var browser=mvc.perform(get(url.getPath()+"?"+url.getRawQuery()).header("Host","127.0.0.1:8080"))
                .andExpect(status().isSeeOther()).andReturn().getResponse();
            String state=URI.create(browser.getHeader("Location")).getQuery().split("state=")[1];
            String binding=browser.getHeader("Set-Cookie").split(";",2)[0].split("=",2)[1];
            mvc.perform(get("/paytm/callback?success=true&state="+state+"&requestToken=fixture")
                .header("Host","127.0.0.1:8080").cookie(new Cookie("marketbrain_paytm_supervised",binding))).andExpect(status().isOk());
            // A valid local token does not waive browser-origin or forwarding restrictions.
            for(String h:new String[]{"Origin","Forwarded","X-Forwarded-For","X-Forwarded-Host","X-Forwarded-Proto"})
                mvc.perform(api("quote").header(h,"untrusted").content("{\"securityId\":3456}"))
                    .andExpect(status().isUnauthorized()).andExpect(header().string("Cache-Control","no-store"));
            assertThat(sends.get()).isEqualTo(2);
            String expected=switch(defect){case "fresh"->"FRESH_QUOTE_OBSERVED";case "stale"->"STALE_QUOTE";case "future"->"FUTURE_TIMESTAMP";case "missing"->"NO_QUOTE";case "wrongId"->"MALFORMED_QUOTE";case "rateLimit"->"PAYTM_HTTP_429";default->"PAYTM_TRANSPORT_OR_JSON_FAILED";};
            var response=mvc.perform(api("quote").content("{\"securityId\":3456,\"fresh\":true,\"lastPrice\":999,\"ordersEnabled\":true,\"mappingVerified\":true}"))
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control","no-store"))
                .andExpect(jsonPath("$.status").value(expected)).andExpect(jsonPath("$.fresh").value(defect.equals("fresh")))
                .andExpect(jsonPath("$.ordersEnabled").value(false)).andExpect(jsonPath("$.mappingVerified").value(false))
                .andReturn().getResponse().getContentAsString();
            assertThat(response).doesNotContain("PRIVATE_","read-fixture","trade-unused");
            if(defect.equals("fresh"))assertThat(json.readTree(response).path("lastPrice").decimalValue()).isEqualByComparingTo("423.75");
            mvc.perform(api("lock")).andExpect(jsonPath("$.status").value("LOCKED"));
            mvc.perform(api("quote").content("{\"securityId\":3456}"))
                .andExpect(jsonPath("$.status").value("SUPERVISED_SESSION_LOCKED"));
            assertThat(sends.get()).isEqualTo(3);
        }finally{controller.shutdown();}
    }
}
