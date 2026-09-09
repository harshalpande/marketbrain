package in.marketbrain.training;

import in.marketbrain.feature.FeatureUniversePreviewService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class SwingTrainingDatasetPreviewServiceTest {

    @Test
    void rejectsAWindowWithoutAnyFutureLabelPeriodBeforeReadingData() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        FeatureUniversePreviewService featureService = mock(FeatureUniversePreviewService.class);
        SwingOutcomeLabelCalculator calculator = mock(SwingOutcomeLabelCalculator.class);
        SwingTrainingDatasetManifestHasher hasher = mock(SwingTrainingDatasetManifestHasher.class);
        SwingTrainingDatasetPreviewService service = new SwingTrainingDatasetPreviewService(
                jdbc, featureService, calculator, hasher);
        LocalDate date = LocalDate.of(2026, 6, 5);

        assertThatThrownBy(() -> service.preview(date, date, 50))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("must be after");
        verifyNoInteractions(jdbc, featureService, calculator, hasher);
    }
}
