package in.marketbrain.feature;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DailyFeatureAutomationPreviewControllerTest {

    @Test
    void mapsAnIncompleteDailyRunToConflict() {
        DailyFeatureAutomationPreviewService service = mock(DailyFeatureAutomationPreviewService.class);
        DailyFeatureAutomationPreviewController controller =
                new DailyFeatureAutomationPreviewController(service);
        LocalDate targetDate = LocalDate.of(2026, 9, 8);
        when(service.preview(targetDate)).thenThrow(new IllegalStateException("not complete"));

        assertThatThrownBy(() -> controller.preview(targetDate))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        exception -> org.assertj.core.api.Assertions.assertThat(exception.getStatusCode())
                                .isEqualTo(HttpStatus.CONFLICT));
    }
}
