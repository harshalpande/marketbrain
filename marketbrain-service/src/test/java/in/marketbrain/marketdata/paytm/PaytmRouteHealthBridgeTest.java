package in.marketbrain.marketdata.paytm;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import in.marketbrain.configuration.MarketBrainProperties;
import static org.assertj.core.api.Assertions.*;

class PaytmRouteHealthBridgeTest {
    static final String TOKEN="h".repeat(32), READ="r".repeat(32);
    final AtomicLong n=new AtomicLong(), w=new AtomicLong();
    final AtomicInteger calls=new AtomicInteger();
    final PaytmApplicationRoute route=new PaytmApplicationRoute(true,n::get,w::get,()->{
        calls.incrementAndGet();return new PaytmGatewayTransport.Observation("TLS_RESPONSE",503,true,"NONE");});
    final PaytmRouteHealthBridge bridge=new PaytmRouteHealthBridge(route,TOKEN,"PAPER",READ,n::get);
    final PaytmRouteHealthController controller=new PaytmRouteHealthController(bridge);
    PaytmRouteHealthBridge.Evidence evidence(PaytmRouteHealthBridge.Receipt c) {
        return new PaytmRouteHealthBridge.Evidence(c.challenge(),c.bootId(),true,true,0,0);
    }
    MockHttpServletRequest request(String body) {
        var r=new MockHttpServletRequest();r.addHeader("Host","127.0.0.1:8080");
        r.addHeader("X-MarketBrain-Paytm-Health","diagnostic-health");
        r.addHeader("X-MarketBrain-Paytm-Health-Token",TOKEN);
        r.setContentType("application/json");r.setContent(body.getBytes(StandardCharsets.UTF_8));return r;
    }
    String payload(PaytmRouteHealthBridge.Receipt c) {
        return "{\"challenge\":\""+c.challenge()+"\",\"bootId\":\""+c.bootId()+"\",\"synchronizedClock\":true,\"transportHealthy\":true,\"lowerOffsetSeconds\":0,\"upperOffsetSeconds\":0}";
    }
    @Test void springDefaultsDisabledAndTokenCannotReuseReadAuthority() {
        new ApplicationContextRunner().withBean(MarketBrainProperties.class,()->PaytmApplicationRouteTest.properties(false,""))
            .withUserConfiguration(PaytmApplicationRoute.class,PaytmRouteHealthBridge.class,PaytmRouteHealthController.class)
            .run(c->{assertThat(c).hasNotFailed();assertThat(c.getBean(PaytmRouteHealthBridge.class).enabled()).isFalse();});
        new ApplicationContextRunner().withBean(MarketBrainProperties.class,()->PaytmApplicationRouteTest.properties(false,""))
            .withPropertyValues("marketbrain.paytm-money.health-token="+TOKEN,"marketbrain.paper.read-token="+READ)
            .withUserConfiguration(PaytmApplicationRoute.class,PaytmRouteHealthBridge.class,PaytmRouteHealthController.class)
            .run(c->{assertThat(c).hasNotFailed();assertThat(c.getBean(PaytmRouteHealthBridge.class).enabled()).isTrue();});
        for(String mode:new String[]{"LIVE","paper"}) assertThat(new PaytmRouteHealthBridge(route,TOKEN,mode,READ,n::get).enabled()).isFalse();
        assertThat(new PaytmRouteHealthBridge(route,TOKEN,"PAPER",TOKEN,n::get).enabled()).isFalse();
        assertThat(new PaytmRouteHealthBridge(route,"short","PAPER",READ,n::get).enabled()).isFalse();
    }
    @Test void validEvidenceRequiresExplicitArmAndDoesNotCallNetwork() {
        assertThat(bridge.submit(evidence(bridge.challenge())).accepted()).isTrue();
        route.head();assertThat(calls.get()).isZero();route.arm();assertThat(route.head().tlsVerified()).isTrue();
        assertThat(calls.get()).isEqualTo(1);
    }
    @Test void replayRevokesAnArmedLease() {
        var e=evidence(bridge.challenge());bridge.submit(e);route.arm();
        assertThat(bridge.submit(e).accepted()).isFalse();route.head();assertThat(calls.get()).isZero();
    }
    @Test void expiryBoundaryWrongBootAndReplacedChallengesRejected() {
        var old=evidence(bridge.challenge());bridge.challenge();assertThat(bridge.submit(old).accepted()).isFalse();
        var c=bridge.challenge();assertThat(bridge.submit(new PaytmRouteHealthBridge.Evidence(c.challenge(),"wrong",true,true,0,0)).accepted()).isFalse();
        var e=evidence(bridge.challenge());n.set(10_000_000_000L);w.set(10000);
        assertThat(bridge.submit(e).accepted()).isFalse();assertThat(route.arm().status()).isEqualTo("TIMING_BLOCKED");
    }
    @Test void unhealthyOrInvalidBoundsLock() {
        for(double[] b:new double[][]{{6,7},{1,-1},{Double.NaN,0},{0,Double.POSITIVE_INFINITY}}) {
            var c=bridge.challenge();assertThat(bridge.submit(new PaytmRouteHealthBridge.Evidence(c.challenge(),c.bootId(),true,true,b[0],b[1])).accepted()).isFalse();
        }
        var c=bridge.challenge();assertThat(bridge.submit(new PaytmRouteHealthBridge.Evidence(c.challenge(),c.bootId(),false,true,0,0)).accepted()).isFalse();
        c=bridge.challenge();assertThat(bridge.submit(new PaytmRouteHealthBridge.Evidence(c.challenge(),c.bootId(),true,false,0,0)).accepted()).isFalse();
        route.arm();route.head();assertThat(calls.get()).isZero();
    }
    @Test void refreshCannotExtendLeaseOrRestoreAuthority() {
        bridge.submit(evidence(bridge.challenge()));route.arm();
        for(int i=1;i<=5;i++){n.set(i*20_000_000_000L);w.set(i*20000L);assertThat(bridge.submit(evidence(bridge.challenge())).accepted()).isTrue();}
        route.head();assertThat(calls.get()).isZero();
        bridge.submit(evidence(bridge.challenge()));route.head();assertThat(calls.get()).isZero();
    }
    @Test void controllerAuthenticatesBeforeReadingBody() {
        var r=new MockHttpServletRequest(){@Override public jakarta.servlet.ServletInputStream getInputStream(){throw new AssertionError("Unauthenticated body read");}};
        assertThat(controller.command("submit",r).getStatusCode().value()).isEqualTo(401);
        var wrong=request("{}");wrong.removeHeader("X-MarketBrain-Paytm-Health-Token");wrong.addHeader("X-MarketBrain-Paytm-Health-Token",READ);
        assertThat(controller.command("submit",wrong).getStatusCode().value()).isEqualTo(401);
    }
    @Test void controllerRejectsForwardingOriginOversizeAndCommands() {
        for(String h:new String[]{"Origin","Forwarded","X-Forwarded-For","X-Forwarded-Host","Transfer-Encoding"}) {
            var r=request("");r.addHeader(h,"unexpected");assertThat(controller.command("challenge",r).getStatusCode().value()).isEqualTo(400);
        }
        assertThat(controller.command("submit",request("x".repeat(2049))).getStatusCode().value()).isEqualTo(400);
        assertThat(controller.command("arm",request("")).getStatusCode().value()).isEqualTo(400);
        var r=request("");r.removeHeader("Host");r.addHeader("Host","external");assertThat(controller.command("challenge",r).getStatusCode().value()).isEqualTo(400);
    }
    @Test void controllerRejectsMalformedMissingDuplicateCoercedAndTrailingJson() {
        String good=payload(bridge.challenge());
        for(String bad:new String[]{"{}","null",good+" {}",good.replace("true","\"true\""),good.replace("\"lowerOffsetSeconds\":0","\"lowerOffsetSeconds\":null"),good.replace("\"lowerOffsetSeconds\":0","\"extra\":0"),good.replace("\"lowerOffsetSeconds\":0","\"lowerOffsetSeconds\":0,\"lowerOffsetSeconds\":0")})
            assertThat(controller.command("submit",request(bad)).getStatusCode().value()).isEqualTo(400);
        assertThat(calls.get()).isZero();
    }
    @Test void controllerChallengeSubmitReplayRoundtrip() throws Exception {
        var mvc=org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/api/v1/paytm/route-health/challenge")
            .header("Host","127.0.0.1:8080").header("X-MarketBrain-Paytm-Health","diagnostic-health")
            .header("X-MarketBrain-Paytm-Health-Token",TOKEN))
            .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isOk());
        var response=controller.command("challenge",request(""));
        assertThat(response.getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
        var c=(PaytmRouteHealthBridge.Receipt)response.getBody();
        var accepted=(PaytmRouteHealthBridge.Receipt)controller.command("submit",request(payload(c))).getBody();
        assertThat(accepted.accepted()).isTrue();assertThat(accepted.ordersEnabled()).isFalse();
        var replay=(PaytmRouteHealthBridge.Receipt)controller.command("submit",request(payload(c))).getBody();assertThat(replay.accepted()).isFalse();
        assertThat(calls.get()).isZero();
    }
}
