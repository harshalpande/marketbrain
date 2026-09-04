package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class QualityResolutionServiceTest {

    private final QualityResolutionService service = new QualityResolutionService(null, null);

    @Test
    void rejectsAnotherCurrentResolutionForTheSameFinding() {
        assertThatThrownBy(() -> service.rejectExistingCurrentResolution(1))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("already exists");
    }

    @Test
    void permitsAResolutionWhenTheFindingHasNoCurrentResolution() {
        assertThatCode(() -> service.rejectExistingCurrentResolution(0)).doesNotThrowAnyException();
        assertThatCode(() -> service.rejectExistingCurrentResolution(null)).doesNotThrowAnyException();
    }
}
