package in.marketbrain.marketdata.daily;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class DailyEnrichmentPlannerTest {

    private final DailyEnrichmentPlanner planner = new DailyEnrichmentPlanner();
    private final UUID snapshotId = UUID.fromString("11111111-2222-3333-4444-555555555555");
    private final LocalDate target = LocalDate.of(2026, 9, 7);

    @Test
    void classifiesCurrentFetchAndMissingBaselineWithoutWriting() {
        DailyEnrichmentPlanner.Plan plan = planner.plan(snapshotId, target, 366, List.of(
                new DailyEnrichmentPlanner.Candidate(2L, "NSE_EQ|BBB", "BBB", target.minusDays(2)),
                new DailyEnrichmentPlanner.Candidate(1L, "NSE_EQ|AAA", "AAA", target),
                new DailyEnrichmentPlanner.Candidate(3L, "NSE_EQ|CCC", "CCC", null)));

        DailyEnrichmentPreview preview = plan.preview();
        assertThat(preview.instrumentCount()).isEqualTo(3);
        assertThat(preview.upToDateInstruments()).isEqualTo(1);
        assertThat(preview.fetchInstruments()).isEqualTo(1);
        assertThat(preview.blockedInstruments()).isEqualTo(1);
        assertThat(preview.earliestFromDate()).isEqualTo(target.minusDays(1));
        assertThat(preview.totalRequestedCalendarDays()).isEqualTo(2);
        assertThat(preview.databaseWritesPerformed()).isFalse();
        assertThat(preview.manifestHash()).matches("[0-9a-f]{64}");
        assertThat(preview.instruments()).extracting(DailyEnrichmentPreview.Instrument::status)
                .containsExactly("UP_TO_DATE", "FETCH_REQUIRED", "NO_BASELINE");
        assertThat(plan.fetchItems()).extracting(DailyEnrichmentPlanner.PlannedInstrument::symbol)
                .containsExactly("BBB");
    }

    @Test
    void manifestIsDeterministicRegardlessOfInputOrdering() {
        var first = new DailyEnrichmentPlanner.Candidate(1L, "NSE_EQ|AAA", "AAA", target.minusDays(1));
        var second = new DailyEnrichmentPlanner.Candidate(2L, "NSE_EQ|BBB", "BBB", target.minusDays(2));

        String forward = planner.plan(snapshotId, target, 366, List.of(first, second))
                .preview().manifestHash();
        String reverse = planner.plan(snapshotId, target, 366, List.of(second, first))
                .preview().manifestHash();

        assertThat(forward).isEqualTo(reverse);
    }

    @Test
    void blocksCatchupBeyondConfiguredLimit() {
        DailyEnrichmentPreview preview = planner.plan(snapshotId, target, 30, List.of(
                new DailyEnrichmentPlanner.Candidate(
                        1L, "NSE_EQ|AAA", "AAA", target.minusDays(31))))
                .preview();

        assertThat(preview.fetchInstruments()).isZero();
        assertThat(preview.blockedInstruments()).isEqualTo(1);
        assertThat(preview.instruments().getFirst().status()).isEqualTo("CATCHUP_LIMIT_EXCEEDED");
    }
}
