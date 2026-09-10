package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

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

    @Test
    void connectivityEpisodesHaveStableButDistinctNotificationKeys() {
        UUID jobId = UUID.randomUUID();
        Instant firstEpisode = Instant.parse("2026-09-10T10:00:00Z");
        Instant secondEpisode = Instant.parse("2026-09-10T11:00:00Z");

        String first = HistoricalBackfillWorker.connectivityKey(
                jobId, "WAIT", firstEpisode);

        assertThat(HistoricalBackfillWorker.connectivityKey(
                jobId, "WAIT", firstEpisode)).isEqualTo(first);
        assertThat(HistoricalBackfillWorker.connectivityKey(
                jobId, "WAIT", secondEpisode)).isNotEqualTo(first);
        assertThat(HistoricalBackfillWorker.connectivityKey(
                jobId, "RECOVERY", firstEpisode)).isNotEqualTo(first);
    }

    @Test
    void recoveryNoticeRequiresAnEarlierWaitNoticeAndAConfiguredChannel() {
        assertThat(HistoricalBackfillWorker.shouldSendConnectivityRecovery(true, true)).isTrue();
        assertThat(HistoricalBackfillWorker.shouldSendConnectivityRecovery(false, true)).isFalse();
        assertThat(HistoricalBackfillWorker.shouldSendConnectivityRecovery(true, false)).isFalse();
    }
}
