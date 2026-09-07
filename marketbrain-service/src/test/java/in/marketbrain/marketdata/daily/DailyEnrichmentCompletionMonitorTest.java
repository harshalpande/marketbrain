package in.marketbrain.marketdata.daily;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class DailyEnrichmentCompletionMonitorTest {

    @Test
    void cleanOutcomeRequiresCompleteCoverageAndNoRejectedRows() {
        var clean = outcome("COMPLETED", 500, 500, 0, 0, 0);
        var missing = outcome("COMPLETED", 500, 500, 0, 0, 1);
        var rejected = outcome("COMPLETED", 500, 500, 0, 1, 0);

        assertThat(clean.clean()).isTrue();
        assertThat(missing.clean()).isFalse();
        assertThat(rejected.clean()).isFalse();
        assertThat(DailyEnrichmentCompletionMonitor.completionMessage(clean))
                .contains("[DAILY DATA COMPLETE] PAPER MODE")
                .contains("no trading action is required");
        assertThat(DailyEnrichmentCompletionMonitor.warningMessage(missing))
                .contains("[DAILY DATA WARNING] PAPER MODE")
                .contains("stale or incomplete data remains non-actionable");
    }

    private DailyEnrichmentCompletionMonitor.RunOutcome outcome(
            String status,
            int total,
            int completed,
            int failed,
            int rejected,
            int missing
    ) {
        return new DailyEnrichmentCompletionMonitor.RunOutcome(
                UUID.randomUUID(), LocalDate.of(2026, 9, 7), status, 500,
                total, completed, failed, completed, rejected, missing);
    }
}
