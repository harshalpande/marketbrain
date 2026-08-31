package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.LinkedHashMap;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PaytmHistoricalCandleRequestTest {

    @Test
    void producesDocumentedEquityCandleRequestShape() {
        var request = new PaytmHistoricalCandleRequest(
                "NSE", "INFY", "ES", "DAY",
                LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31));

        var expected = new LinkedHashMap<String, String>();
        expected.put("exchange", "NSE");
        expected.put("symbol", "INFY");
        expected.put("instType", "ES");
        expected.put("interval", "DAY");
        expected.put("fromDate", "2026-08-01");
        expected.put("toDate", "2026-08-31");

        assertThat(request.asRequestBody()).containsExactlyEntriesOf(expected);
    }

    @Test
    void rejectsAnInvalidDateRangeBeforeAnyProviderCall() {
        assertThatThrownBy(() -> new PaytmHistoricalCandleRequest(
                "NSE", "INFY", "ES", "DAY",
                LocalDate.of(2026, 8, 31), LocalDate.of(2026, 8, 1)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("toDate");
    }
}
