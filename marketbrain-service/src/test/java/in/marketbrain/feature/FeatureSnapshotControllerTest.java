package in.marketbrain.feature;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.NoSuchElementException;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class FeatureSnapshotControllerTest {

    private static final LocalDate AS_OF = LocalDate.of(2026, 9, 8);
    private static final String HASH = "a".repeat(64);

    @Test
    void delegatesAnExplicitReviewedPersistenceRequest() {
        FeatureSnapshotService service = mock(FeatureSnapshotService.class);
        FeatureSnapshotController controller = new FeatureSnapshotController(service);
        FeatureSnapshotRequest request = new FeatureSnapshotRequest(AS_OF, HASH, "Harshal Pande");
        FeatureSnapshotSummary expected = new FeatureSnapshotSummary(
                "COMPLETED", UUID.randomUUID(), UUID.randomUUID(), AS_OF, "TECHNICAL_V1",
                HASH, "Harshal Pande", 500, 485, 15, 15, 0, 0, 500, 0, 0, true, "done");
        when(service.persist(request)).thenReturn(expected);

        assertThat(controller.persist(AS_OF, HASH, "Harshal Pande")).isSameAs(expected);
    }

    @Test
    void mapsAChangedManifestToConflict() {
        FeatureSnapshotService service = mock(FeatureSnapshotService.class);
        FeatureSnapshotController controller = new FeatureSnapshotController(service);
        FeatureSnapshotRequest request = new FeatureSnapshotRequest(AS_OF, HASH, "Harshal Pande");
        when(service.persist(request)).thenThrow(new IllegalStateException("changed"));

        assertThatThrownBy(() -> controller.persist(AS_OF, HASH, "Harshal Pande"))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        exception -> assertThat(exception.getStatusCode()).isEqualTo(HttpStatus.CONFLICT));
    }

    @Test
    void mapsAMissingQualityRunToNotFound() {
        FeatureSnapshotService service = mock(FeatureSnapshotService.class);
        FeatureSnapshotController controller = new FeatureSnapshotController(service);
        UUID runId = UUID.randomUUID();
        when(service.quality(runId, HASH)).thenThrow(new NoSuchElementException("missing"));

        assertThatThrownBy(() -> controller.quality(runId, HASH))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        exception -> assertThat(exception.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND));
    }
}
