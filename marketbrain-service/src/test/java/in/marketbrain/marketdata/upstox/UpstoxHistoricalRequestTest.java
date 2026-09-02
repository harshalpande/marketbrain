package in.marketbrain.marketdata.upstox;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class UpstoxHistoricalRequestTest {

    @Test
    void normalizesUnitAndBuildsAnAuditFriendlyIntervalCode() {
        var request = new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "DAYS", 1,
                LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31));

        assertThat(request.unit()).isEqualTo("days");
        assertThat(request.intervalCode()).isEqualTo("days:1");
    }

    @Test
    void rejectsOversizedManualBackfill() {
        assertThatThrownBy(() -> new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "days", 1,
                LocalDate.of(2025, 1, 1), LocalDate.of(2026, 2, 1)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("one year");
    }

    @Test
    void rejectsProviderUnsupportedIntervalBeforeCallingUpstox() {
        assertThatThrownBy(() -> new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "days", 2,
                LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("interval");
    }
}
