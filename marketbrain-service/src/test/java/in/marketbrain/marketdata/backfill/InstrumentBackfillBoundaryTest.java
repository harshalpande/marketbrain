package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class InstrumentBackfillBoundaryTest {

    private static final LocalDate REQUESTED_FROM = LocalDate.of(2011, 9, 3);

    @Test
    void startsAtOfficialListingDateWhenItFallsInsideTheRequestedWindow() {
        assertThat(HistoricalBackfillJobService.effectiveFromDate(
                REQUESTED_FROM, LocalDate.of(2020, 10, 5)))
                .isEqualTo(LocalDate.of(2020, 10, 5));
    }

    @Test
    void retainsRequestedStartWhenListingDateIsUnknownOrOlder() {
        assertThat(HistoricalBackfillJobService.effectiveFromDate(REQUESTED_FROM, null))
                .isEqualTo(REQUESTED_FROM);
        assertThat(HistoricalBackfillJobService.effectiveFromDate(
                REQUESTED_FROM, LocalDate.of(2000, 1, 1)))
                .isEqualTo(REQUESTED_FROM);
    }
}
