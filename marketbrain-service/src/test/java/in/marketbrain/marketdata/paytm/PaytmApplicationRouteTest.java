package in.marketbrain.marketdata.paytm;

import in.marketbrain.configuration.MarketBrainProperties;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PaytmApplicationRouteTest {
    private static final String TOKEN = "a".repeat(40);
    private static final PaytmGatewayTransport.Observation TLS = new PaytmGatewayTransport.Observation("TLS_RESPONSE",503,true,"NONE");
    static MarketBrainProperties properties(boolean enabled, String token) {
        return new MarketBrainProperties("PAPER", null, null, null,
                new MarketBrainProperties.PaytmMoney("https://developer.paytmmoney.com", enabled, token), null, null);
    }
    @Test void startsLockedAndNeverCallsTransport() {
        var calls = new AtomicInteger(); var route = new PaytmApplicationRoute(true, System::nanoTime, () -> {calls.incrementAndGet();return TLS;});
        assertThat(route.status().state()).isEqualTo("LOCKED"); assertThat(route.head().status()).isEqualTo("LOCKED");
        assertThat(calls.get()).isZero();
    }
    @Test void fixedBudgetAndExplicitLock() {
        var calls = new AtomicInteger(); var route = new PaytmApplicationRoute(true, System::nanoTime, () -> {calls.incrementAndGet();return TLS;});
        route.arm(); for(int i=0;i<4;i++) assertThat(route.head().tlsVerified()).isTrue();
        assertThat(route.head().status()).isEqualTo("LOCKED"); assertThat(calls.get()).isEqualTo(4);
        route.arm(); route.lock(); assertThat(route.head().status()).isEqualTo("LOCKED");
    }
    @Test void monotonicExpiryAndFreshInstanceLocked() {
        var time = new AtomicLong(); var route = new PaytmApplicationRoute(true, time::get, () -> TLS);
        route.arm(); time.set(Duration.ofMinutes(20).toNanos()); assertThat(route.head().status()).isEqualTo("LOCKED");
        var fresh = new PaytmApplicationRoute(true, time::get, () -> TLS);
        assertThat(fresh.status().bootId()).isNotEqualTo(route.status().bootId()); assertThat(fresh.status().state()).isEqualTo("LOCKED");
    }
    @Test void networkFailureRelocksAndRequiresExplicitRearm() {
        var route = new PaytmApplicationRoute(true,System::nanoTime,()->new PaytmGatewayTransport.Observation("TRANSPORT_FAILED",0,false,"ConnectException"));
        route.arm(); assertThat(route.head().state()).isEqualTo("LOCKED"); assertThat(route.head().status()).isEqualTo("LOCKED");
    }
    @Test void exceptionsDoNotLeakAndRelock() {
        var route = new PaytmApplicationRoute(true,System::nanoTime,()->{throw new IllegalStateException("SECRET");});
        route.arm(); assertThat(route.head().toString()).doesNotContain("SECRET").contains("INTERNAL_FAILURE");
        assertThat(route.status().state()).isEqualTo("LOCKED");
    }
    @Test void configuredBrokerCannotBeArmed() {
        for(var p : new MarketBrainProperties[]{properties(true,""),properties(false,"token"),properties(true,"token")}) {
            var route = new PaytmApplicationRoute(p); assertThat(route.arm().status()).isEqualTo("CONFIGURATION_BLOCKED");
            assertThat(route.head().status()).isEqualTo("LOCKED");
        }
    }
    @Test void historicalClientCannotSendEvenWhenConfigured() {
        assertThat(new PaytmMoneyHistoricalClient(properties(true,"secret")).fetchCandles(null).status())
                .isEqualTo("AUTHENTICATION_AND_DATA_INTEGRATION_PENDING");
        assertThat(new PaytmMoneyHistoricalClient(properties(false,"")).fetchCandles(null).status()).isEqualTo("NOT_CONFIGURED");
    }
    @Test void springRegistersActualBeansAndRestartsLocked() {
        var runner = new ApplicationContextRunner().withBean(MarketBrainProperties.class,()->properties(false,""))
                .withUserConfiguration(PaytmApplicationRoute.class,PaytmApplicationRouteController.class,PaytmMoneyHistoricalClient.class)
                .withPropertyValues("marketbrain.paper.read-token="+TOKEN);
        var id = new String[1];
        runner.run(c->{assertThat(c).hasNotFailed().hasSingleBean(PaytmApplicationRoute.class).hasSingleBean(PaytmMoneyHistoricalClient.class);
            var r=c.getBean(PaytmApplicationRoute.class);id[0]=r.status().bootId();assertThat(r.status().state()).isEqualTo("LOCKED");r.arm();});
        runner.run(c->{var r=c.getBean(PaytmApplicationRoute.class);assertThat(r.status().bootId()).isNotEqualTo(id[0]);assertThat(r.status().state()).isEqualTo("LOCKED");});
    }
    @Test void controllerAuthenticationAndInputRejection() throws Exception {
        var route = new PaytmApplicationRoute(true,System::nanoTime,()->TLS);
        var mvc=MockMvcBuilders.standaloneSetup(new PaytmApplicationRouteController(route,TOKEN,"PAPER")).build();
        mvc.perform(post("/api/v1/paytm/route/arm")).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/paytm/route/arm").header("X-MarketBrain-Paper-Read-Token",TOKEN)).andExpect(status().isBadRequest());
        for(String header : new String[]{"Origin","Forwarded","X-Forwarded-For","X-Forwarded-Host"})
            mvc.perform(post("/api/v1/paytm/route/arm").header("Host","127.0.0.1:8080")
                    .header("X-MarketBrain-Paper-Read-Token",TOKEN).header("X-MarketBrain-Paytm-Route","credential-free").header(header,"bad"))
                    .andExpect(status().isBadRequest());
        for(String path : new String[]{"head?target=evil","order","arm"}) {
            var req=post("/api/v1/paytm/route/"+path).header("Host","127.0.0.1:8080")
                    .header("X-MarketBrain-Paper-Read-Token",TOKEN).header("X-MarketBrain-Paytm-Route","credential-free");
            if(path.equals("arm"))req.content("not allowed");
            mvc.perform(req).andExpect(status().isBadRequest());
        }
        assertThat(route.status().state()).isEqualTo("LOCKED");
    }
    @Test void controllerPositiveContractAndNoBrokerAuthority() throws Exception {
        var mvc=MockMvcBuilders.standaloneSetup(new PaytmApplicationRouteController(new PaytmApplicationRoute(true,System::nanoTime,()->TLS),TOKEN,"PAPER")).build();
        for(String command : new String[]{"status","arm","head","lock"})
            mvc.perform(post("/api/v1/paytm/route/"+command).header("Host","127.0.0.1:8080")
                    .header("X-MarketBrain-Paper-Read-Token",TOKEN).header("X-MarketBrain-Paytm-Route","credential-free"))
                    .andExpect(status().isOk()).andExpect(header().string("Cache-Control","no-store"))
                    .andExpect(jsonPath("$.applicationProcessVerified").value(true)).andExpect(jsonPath("$.credentialsUsed").value(false))
                    .andExpect(jsonPath("$.ordersEnabled").value(false));
    }
}
