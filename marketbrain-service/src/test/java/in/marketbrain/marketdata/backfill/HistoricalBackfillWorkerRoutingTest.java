package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class HistoricalBackfillWorkerRoutingTest {

    @Test
    void usesIntradayOnlyForTodaysDailyTarget() {
        LocalDate today = LocalDate.of(2026, 9, 8);

        assertThat(HistoricalBackfillWorker.requiresIntradayTarget("DAILY", today, today)).isTrue();
        assertThat(HistoricalBackfillWorker.requiresIntradayTarget(
                "DAILY", today.minusDays(1), today)).isFalse();
        assertThat(HistoricalBackfillWorker.requiresIntradayTarget("EXPANSION", today, today)).isFalse();
        assertThat(HistoricalBackfillWorker.requiresIntradayTarget("PILOT", today, today)).isFalse();
    }
}
