package in.marketbrain.feature;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DailyFeatureSnapshotAutomationControllerTest {

    @Test
    void delegatesAnExplicitTargetDate() {
        DailyFeatureSnapshotAutomationService service = mock(DailyFeatureSnapshotAutomationService.class);
        DailyFeatureSnapshotAutomationController controller =
                new DailyFeatureSnapshotAutomationController(service);
        LocalDate targetDate = LocalDate.of(2026, 9, 8);
        DailyFeatureSnapshotAutomationStatus expected = new DailyFeatureSnapshotAutomationStatus(
                true, targetDate, targetDate, "COMPLETED", 1,
                null, null, null, 485, 15, null, "SENT", "complete");
        when(service.status(targetDate)).thenReturn(expected);

        assertThat(controller.status(targetDate)).isSameAs(expected);
    }
}
