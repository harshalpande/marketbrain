package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PrototypeSwingTypedDecisionPrimitivePreviewControllerTest {

    @Test
    void delegatesTypedDecisionPrimitivePreviewRequest() {
        PrototypeSwingTypedDecisionPrimitivePreviewService service =
                mock(PrototypeSwingTypedDecisionPrimitivePreviewService.class);
        PrototypeSwingTypedDecisionPrimitivePreviewController controller =
                new PrototypeSwingTypedDecisionPrimitivePreviewController(service);
        UUID runId = UUID.randomUUID();
        PrototypeSwingTypedDecisionPrimitiveRequest request =
                new PrototypeSwingTypedDecisionPrimitiveRequest(runId, "DIFFICULT_TRAPS", 0, 4, 20);
        PrototypeSwingTypedDecisionPrimitivePreview expected =
                new PrototypeSwingTypedDecisionPrimitivePreview(
                        "REVIEW_REQUIRED",
                        runId,
                        LocalDate.of(2026, 6, 5),
                        LocalDate.of(2026, 9, 8),
                        "DIFFICULT_TRAPS",
                        0,
                        4,
                        0,
                        20,
                        "TYPED_DECISION_V1",
                        "GBNF_V1",
                        "root ::= \"{}\"",
                        List.of("REJECT"),
                        List.of("LOW"),
                        List.of("YES"),
                        List.of("VERY_LOW"),
                        List.of("LOW"),
                        List.of("TRAP_RISK"),
                        List.of(),
                        false,
                        0,
                        0,
                        0,
                        0,
                        false,
                        "review"
                );
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
