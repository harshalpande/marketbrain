package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class PaytmLoginPreparationTest {
    @Test void nativeVerifierChecksAllPass() {
        var checks = PaytmLoginPreparationVerification.run();
        assertThat(checks).hasSize(38);
        assertThat(checks).allMatch(PaytmLoginPreparationVerification.Check::passed);
        assertThat(checks.stream().map(PaytmLoginPreparationVerification.Check::name).distinct().count()).isEqualTo(38);
    }
}
