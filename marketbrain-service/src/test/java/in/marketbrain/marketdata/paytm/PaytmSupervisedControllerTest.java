package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.assertj.core.api.Assertions.*;

class PaytmSupervisedControllerTest {
    private static final String TOKEN="a".repeat(40);
    @Test void featureDisabledByDefaultAndRequiresPaperAndToken() {
        new ApplicationContextRunner().withUserConfiguration(PaytmSupervisedController.class)
                .run(c->assertThat(c).doesNotHaveBean(PaytmSupervisedController.class));
        new ApplicationContextRunner().withUserConfiguration(PaytmSupervisedController.class)
                .withPropertyValues("marketbrain.paytm-supervised.enabled=true","marketbrain.paper.read-token="+TOKEN)
                .run(c->assertThat(c).hasSingleBean(PaytmSupervisedController.class));
        assertThatThrownBy(()->new PaytmSupervisedController(TOKEN,"LIVE",false)).hasMessage("SUPERVISED_CONFIGURATION_REJECTED");
        assertThatThrownBy(()->new PaytmSupervisedController(TOKEN,"PAPER",true)).hasMessage("SUPERVISED_CONFIGURATION_REJECTED");
    }
    @Test void unauthorizedAndBrowserOriginsCannotStartCredentialsSession() throws Exception {
        var c=new PaytmSupervisedController(TOKEN,"PAPER",false);
        try {
            var mvc=MockMvcBuilders.standaloneSetup(c).build();
            mvc.perform(post("/api/v1/paytm/supervised/status").header("Host","127.0.0.1:8080")).andExpect(status().isUnauthorized());
            mvc.perform(post("/api/v1/paytm/supervised/status").header("Host","127.0.0.1:8080")
                    .header("X-MarketBrain-Paper-Read-Token",TOKEN).header("X-MarketBrain-Paytm-Supervised","supervised-paper")
                    .header("Origin","http://evil.example")).andExpect(status().isUnauthorized());
            mvc.perform(post("/api/v1/paytm/supervised/status").header("Host","127.0.0.1:8080")
                    .header("X-MarketBrain-Paper-Read-Token",TOKEN).header("X-MarketBrain-Paytm-Supervised","supervised-paper"))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("LOCKED"))
                    .andExpect(jsonPath("$.ordersEnabled").value(false));
            mvc.perform(get("/paytm/callback?state=invalid&requestToken=secret").header("Host","127.0.0.1:8080"))
                    .andExpect(status().isBadRequest()).andExpect(header().string("Cache-Control","no-store"))
                    .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("secret"))));
        } finally { c.shutdown(); }
    }
}
