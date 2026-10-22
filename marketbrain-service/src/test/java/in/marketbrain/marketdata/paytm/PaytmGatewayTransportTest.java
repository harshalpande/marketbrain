package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class PaytmGatewayTransportTest {
    @Test void explicitProxyAndLocalFailureContracts() throws Exception {
        assertThat(PaytmRouteVerification.run()).isEqualTo(18);
    }
}
