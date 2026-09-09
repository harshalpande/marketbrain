package in.marketbrain.news;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class NewsSourcePermissionPreviewControllerTest {

    @Test
    void delegatesTheExactPermissionDraft() {
        NewsSourcePermissionPreviewService service = mock(NewsSourcePermissionPreviewService.class);
        NewsSourcePermissionPreviewController controller = new NewsSourcePermissionPreviewController(service);
        NewsSourcePermissionPreviewRequest request = new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9), "Harshal Pande", List.of());
        NewsSourcePermissionPreview expected = mock(NewsSourcePermissionPreview.class);
        when(service.preview(request)).thenReturn(expected);

        assertThat(controller.preview(request)).isSameAs(expected);
    }
}
