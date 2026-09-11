package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingTrainingDatasetAuditControllerTest {

    @Test
    void delegatesOptionalDatasetRunId() {
        PrototypeSwingTrainingDatasetAuditService service = mock(PrototypeSwingTrainingDatasetAuditService.class);
        PrototypeSwingTrainingDatasetAuditController controller =
                new PrototypeSwingTrainingDatasetAuditController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingTrainingDatasetAudit expected = new PrototypeSwingTrainingDatasetAudit(
                "REVIEW_REQUIRED", runId, "PROTOTYPE_SWING_TRAINING_DATASET_V1",
                "CURRENT_SNAPSHOT_PROTOTYPE", LocalDate.of(2026, 6, 5),
                LocalDate.of(2026, 9, 8), "a".repeat(64), 50,
                "CURRENT_SNAPSHOT_EQUAL_WEIGHT_PROXY", "CURRENT_SNAPSHOT_ONLY",
                500, 476, 476, 0, 24, 0, 0, 500, 1_428,
                List.of(5, 20, 60), List.of(), List.of(), List.of(), List.of(),
                true, true, false, true, true, true, false, 0, 0, 0,
                List.of(), "review");
        when(service.audit(runId)).thenReturn(expected);

        assertThat(controller.audit(runId)).isSameAs(expected);
    }
}
