package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class TradableEquityTrainingUniversePreviewControllerTest {

    @Test
    void delegatesExplicitAsOfAndMinimumHistory() {
        TradableEquityTrainingUniversePreviewService service =
                mock(TradableEquityTrainingUniversePreviewService.class);
        TradableEquityTrainingUniversePreviewController controller =
                new TradableEquityTrainingUniversePreviewController(service);
        LocalDate asOf = LocalDate.of(2026, 9, 8);
        TradableEquityTrainingUniversePreview expected = new TradableEquityTrainingUniversePreview(
                "REVIEW_REQUIRED",
                "TRADEABLE_EQUITY_TRAINING_UNIVERSE_V1",
                "AVAILABLE_NSE_EQUITY_DATA",
                "definition",
                asOf,
                300,
                List.of("NSE_BHAVCOPY", "UPSTOX"),
                "NSE_BHAVCOPY_THEN_UPSTOX",
                500,
                500,
                485,
                15,
                0,
                0,
                10_000,
                9_990,
                10,
                LocalDate.of(2011, 1, 3),
                asOf,
                true,
                false,
                true,
                true,
                false,
                true,
                false,
                0,
                0,
                0,
                "a".repeat(64),
                List.of(),
                List.of(),
                "reviewed");
        when(service.preview(asOf, 300)).thenReturn(expected);

        assertThat(controller.preview(asOf, 300)).isSameAs(expected);
    }
}
