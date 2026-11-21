package in.marketbrain.marketdata.paytm;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class PaytmUniverseMatchControllerTest {
    @Test void disabledUnlessSupervisedAndWiresExistingDatabaseOnlyWhenEnabled(){
        DataSource ds=mock(DataSource.class);
        var context=new ApplicationContextRunner().withUserConfiguration(PaytmSupervisedController.class,PaytmUniverseMatchController.class)
            .withBean(JdbcTemplate.class,()->new JdbcTemplate(ds));
        context.run(c->assertThat(c).doesNotHaveBean(PaytmUniverseMatchController.class));
        context.withPropertyValues("marketbrain.paytm-supervised.enabled=true","marketbrain.paper.read-token="+"a".repeat(40))
            .run(c->assertThat(c).hasSingleBean(PaytmUniverseMatchController.class));
        verifyNoInteractions(ds);
    }
    @Test void unauthorizedAndInvalidSymbolsCannotQueryDatabase()throws Exception{
        DataSource ds=mock(DataSource.class);String token="a".repeat(40);
        var guard=new PaytmSupervisedController(token,"PAPER",false);
        try{
            var mvc=MockMvcBuilders.standaloneSetup(new PaytmUniverseMatchController(guard,new JdbcTemplate(ds))).build();
            mvc.perform(post("/api/v1/paytm/supervised/universe-match").header("Host","127.0.0.1:8080")
                .contentType("application/json").content("{\"symbol\":\"RELIANCE\"}")).andExpect(status().isUnauthorized());
            mvc.perform(post("/api/v1/paytm/supervised/universe-match").header("Host","127.0.0.1:8080")
                .header("X-MarketBrain-Paper-Read-Token",token).header("X-MarketBrain-Paytm-Supervised","supervised-paper")
                .contentType("application/json").content("{\"symbol\":\"bad input\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.snapshotMatched").value(false)).andExpect(header().string("Cache-Control","no-store"));
            verifyNoInteractions(ds);
        }finally{guard.shutdown();}
    }
}
