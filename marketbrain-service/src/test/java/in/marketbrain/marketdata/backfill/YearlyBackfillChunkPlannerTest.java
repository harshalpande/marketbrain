package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class YearlyBackfillChunkPlannerTest {

    private final YearlyBackfillChunkPlanner planner = new YearlyBackfillChunkPlanner();

    @Test
    void createsFifteenContinuousNonOverlappingChunks() {
        LocalDate from = LocalDate.of(2011, 9, 3);
        LocalDate to = LocalDate.of(2026, 9, 1);

        var chunks = planner.plan(from, to);

        assertThat(chunks).hasSize(15);
        assertThat(chunks.getFirst().fromDate()).isEqualTo(from);
        assertThat(chunks.getLast().toDate()).isEqualTo(to);
        for (int index = 1; index < chunks.size(); index++) {
            assertThat(chunks.get(index).fromDate())
                    .isEqualTo(chunks.get(index - 1).toDate().plusDays(1));
        }
    }

    @Test
    void supportsAOneDayRange() {
        LocalDate day = LocalDate.of(2026, 9, 1);

        assertThat(planner.plan(day, day))
                .containsExactly(new YearlyBackfillChunkPlanner.DateChunk(day, day));
    }
}
