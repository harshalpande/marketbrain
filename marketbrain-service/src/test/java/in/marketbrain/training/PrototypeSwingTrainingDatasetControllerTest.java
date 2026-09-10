package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingTrainingDatasetControllerTest {

    @Test
    void delegatesManifestBoundPersistenceRequest() {
        PrototypeSwingTrainingDatasetService service = mock(PrototypeSwingTrainingDatasetService.class);
        PrototypeSwingTrainingDatasetController controller = new PrototypeSwingTrainingDatasetController(service);
        LocalDate asOf = LocalDate.of(2026, 6, 5);
        LocalDate labelThrough = LocalDate.of(2026, 9, 8);
        String manifest = "a".repeat(64);
        PrototypeSwingTrainingDatasetSummary expected = new PrototypeSwingTrainingDatasetSummary(
                "COMPLETED", "CREATED", UUID.randomUUID(),
                "PROTOTYPE_SWING_TRAINING_DATASET_V1", "CURRENT_SNAPSHOT_PROTOTYPE",
                asOf, labelThrough, UUID.randomUUID(), "TECHNICAL_V1", "b".repeat(64),
                manifest, 50, "CURRENT_SNAPSHOT_EQUAL_WEIGHT_PROXY",
                "CURRENT_SNAPSHOT_ONLY", "Harshal Pande", 500, 485, 485, 0,
                15, 0, 0, 500, 1_455, List.of(5, 20, 60),
                true, true, false, true, true, true, 0, 0, 0,
                List.of(), "created");
        when(service.persist(asOf, labelThrough, 50, manifest, "Harshal Pande")).thenReturn(expected);

        assertThat(controller.persist(asOf, labelThrough, 50, manifest, "Harshal Pande"))
                .isSameAs(expected);
    }
}
