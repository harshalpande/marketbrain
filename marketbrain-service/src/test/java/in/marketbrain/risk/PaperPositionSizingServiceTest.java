package in.marketbrain.risk;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

class PaperPositionSizingServiceTest {

    private final PaperPositionSizingService service = new PaperPositionSizingService();

    @Test
    void capsAOneLakhPortfolioWithFivePercentStopAtTwentyThousandRupees() {
        var result = service.size(new BigDecimal("100000"), new BigDecimal("100000"),
                new BigDecimal("100"), new BigDecimal("95"));

        assertThat(result.quantity()).isEqualByComparingTo("200");
        assertThat(result.estimatedNotional()).isEqualByComparingTo("20000");
        assertThat(result.estimatedRisk()).isEqualByComparingTo("1000");
    }
}
