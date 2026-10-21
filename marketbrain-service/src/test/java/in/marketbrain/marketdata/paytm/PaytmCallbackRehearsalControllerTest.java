package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.Cookie;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PaytmCallbackRehearsalControllerTest {
    private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new PaytmCallbackRehearsalController()).build();
    private MockHttpServletRequestBuilder start() {
        return post("/paytm/rehearsal/start").header("Host", "127.0.0.1:8080")
                .header("Origin", "http://127.0.0.1:8080").header("X-MarketBrain-Rehearsal", "synthetic-only");
    }
    private record Flow(URI uri, Cookie cookie) {}
    private Flow begin() throws Exception {
        var response = mvc.perform(start()).andExpect(status().isOk()).andExpect(jsonPath("$.authenticated").value(false))
                .andExpect(header().string("Cache-Control", "no-store")).andReturn().getResponse();
        String callback = new ObjectMapper().readTree(response.getContentAsString()).get("callback").asText();
        String setCookie = response.getHeader("Set-Cookie");
        assertThat(setCookie).contains("HttpOnly", "SameSite=Lax", "Path=/paytm").doesNotContain("Domain=");
        return new Flow(URI.create(callback), response.getCookie("marketbrain_paytm_rehearsal"));
    }
    @Test void defaultAndFalseConfigurationRegisterNothing() {
        var context = new ApplicationContextRunner().withUserConfiguration(PaytmCallbackRehearsalController.class);
        context.run(c -> assertThat(c).doesNotHaveBean(PaytmCallbackRehearsalController.class));
        context.withPropertyValues("marketbrain.paytm-auth.rehearsal.enabled=false")
                .run(c -> assertThat(c).doesNotHaveBean(PaytmCallbackRehearsalController.class));
    }
    @Test void explicitRehearsalRegistersWithoutCredentialsOrDatabase() {
        new ApplicationContextRunner().withUserConfiguration(PaytmCallbackRehearsalController.class)
                .withPropertyValues("marketbrain.paytm-auth.rehearsal.enabled=true")
                .run(c -> assertThat(c).hasNotFailed().hasSingleBean(PaytmCallbackRehearsalController.class));
    }
    @Test void roundTripNeverAuthenticatesAndReplayRejected() throws Exception {
        Flow f = begin();
        mvc.perform(get(f.uri()).header("Host", "127.0.0.1:8080").cookie(f.cookie()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.authenticated").value(false))
                .andExpect(jsonPath("$.status").value("SYNTHETIC_CALLBACK_PASSED_REAL_LOGIN_BLOCKED"))
                .andExpect(header().string("Referrer-Policy", "no-referrer"))
                .andExpect(cookie().maxAge("marketbrain_paytm_rehearsal", 0));
        mvc.perform(get(f.uri()).header("Host", "127.0.0.1:8080").cookie(f.cookie())).andExpect(status().isBadRequest());
    }
    @Test void nonLoopbackCannotStartEvenWithForwardedLoopback() throws Exception {
        mvc.perform(start().with(r -> { r.setRemoteAddr("172.18.0.2"); return r; })) .andExpect(status().isBadRequest());
        mvc.perform(start().header("X-Forwarded-For", "127.0.0.1")).andExpect(status().isBadRequest());
        mvc.perform(start().header("Forwarded", "for=127.0.0.1")).andExpect(status().isBadRequest());
    }
    @Test void hostAndOriginAndHeaderAreRequired() throws Exception {
        mvc.perform(start().with(r -> { r.removeHeader("Host"); return r; })).andExpect(status().isBadRequest());
        mvc.perform(start().with(r -> { r.removeHeader("Origin"); return r; })).andExpect(status().isBadRequest());
        mvc.perform(start().with(r -> { r.removeHeader("X-MarketBrain-Rehearsal"); return r; })).andExpect(status().isBadRequest());
        mvc.perform(start().with(r -> { r.removeHeader("Host"); r.addHeader("Host", "evil.invalid:8080"); return r; })).andExpect(status().isBadRequest());
        mvc.perform(start().with(r -> { r.removeHeader("Origin"); r.addHeader("Origin", "http://evil.invalid"); return r; })).andExpect(status().isBadRequest());
    }
    @Test void missingOrDuplicateCookieRejected() throws Exception {
        Flow f = begin();
        mvc.perform(get(f.uri()).header("Host", "127.0.0.1:8080")).andExpect(status().isBadRequest());
        mvc.perform(get(f.uri()).header("Host", "127.0.0.1:8080").cookie(f.cookie(), f.cookie())).andExpect(status().isBadRequest());
    }
    @Test void wrongBrowserRejected() throws Exception {
        Flow a = begin(); Flow b = begin();
        mvc.perform(get(a.uri()).header("Host", "127.0.0.1:8080").cookie(b.cookie())).andExpect(status().isBadRequest());
    }
    @Test void realTokenRejectedWithoutEchoOrExchange() throws Exception {
        Flow f = begin();
        URI uri = URI.create(f.uri().toString().replace("SYNTHETIC_REHEARSAL_ONLY", "DO_NOT_ECHO_FAKE_REAL_TOKEN"));
        var response = mvc.perform(get(uri).header("Host", "127.0.0.1:8080").cookie(f.cookie()))
                .andExpect(status().isBadRequest()).andExpect(header().string("Cache-Control", "no-store"))
                .andReturn().getResponse();
        assertThat(response.getContentAsString()).doesNotContain("DO_NOT_ECHO", f.cookie().getValue());
    }
    @Test void postCallbackAndGetStartNotAllowed() throws Exception {
        mvc.perform(post("/paytm/callback")).andExpect(status().isMethodNotAllowed());
        mvc.perform(get("/paytm/rehearsal/start")).andExpect(status().isMethodNotAllowed());
    }
    @Test void malformedUnsolicitedAndRemoteCallbacksRejected() throws Exception {
        mvc.perform(get("/paytm/callback").header("Host", "127.0.0.1:8080")).andExpect(status().isBadRequest());
        Flow f = begin();
        mvc.perform(get(f.uri()).header("Host", "127.0.0.1:8080").cookie(f.cookie())
                .with(r -> { r.setRemoteAddr("100.64.0.1"); return r; })).andExpect(status().isBadRequest());
        mvc.perform(get(URI.create(f.uri() + "&state=duplicate")).header("Host", "127.0.0.1:8080").cookie(f.cookie()))
                .andExpect(status().isBadRequest());
    }
}
