package in.marketbrain.news;

import java.time.LocalDate;
import java.util.List;

public record NewsSourcePermissionPreviewRequest(
        LocalDate preparedOn,
        String preparedBy,
        List<NewsSourcePermissionDraft> sources
) {
}
