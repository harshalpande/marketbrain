package in.marketbrain.marketdata.upstox;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class UpstoxIntradayRequestTest {

    @Test
    void acceptsTheDocumentedDailyInterval() {
        var request = new UpstoxIntradayRequest("NSE_EQ|INE009A01021", "DAYS", 1);

        assertThat(request.unit()).isEqualTo("days");
        assertThat(request.intervalCode()).isEqualTo("days:1");
    }

    @Test
    void rejectsUnsupportedDailyIntervals() {
        assertThatThrownBy(() -> new UpstoxIntradayRequest("NSE_EQ|INE009A01021", "days", 2))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
