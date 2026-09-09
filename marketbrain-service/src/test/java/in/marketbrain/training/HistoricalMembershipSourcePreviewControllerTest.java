package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class HistoricalMembershipSourcePreviewControllerTest {

    @Test
    void delegatesImmutableSourceEvidence() {
        HistoricalMembershipSourcePreviewService service = mock(HistoricalMembershipSourcePreviewService.class);
        HistoricalMembershipSourcePreviewController controller =
                new HistoricalMembershipSourcePreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 6, 5);
        byte[] payload = "source".getBytes();
        HistoricalMembershipSourcePreview expected = mock(HistoricalMembershipSourcePreview.class);
        when(service.preview(asOf, "source", "https://example.test/source.csv",
                "a".repeat(64), payload)).thenReturn(expected);

        assertThat(controller.preview(
                asOf, "source", "https://example.test/source.csv",
                "a".repeat(64), payload)).isSameAs(expected);
    }
}
