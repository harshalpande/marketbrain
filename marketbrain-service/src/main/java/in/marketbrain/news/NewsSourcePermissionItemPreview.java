package in.marketbrain.news;

import java.time.LocalDate;
import java.util.List;

public record NewsSourcePermissionItemPreview(
        String sourceKey,
        String displayName,
        NewsSourceType sourceType,
        NewsSourcePermissionStatus permissionStatus,
        String sourceUrl,
        String permissionEvidenceReference,
        LocalDate requestedOn,
        LocalDate decidedOn,
        Integer retentionDays,
        boolean headlineStorageAllowed,
        boolean snippetStorageAllowed,
        boolean fullTextStorageAllowed,
        boolean localAiProcessingAllowed,
        boolean derivedDataRetentionAllowed,
        boolean attributionRequired,
        List<String> permittedFields,
        boolean permissionComplete,
        boolean integrationEligible,
        boolean integrationEnabled,
        String detail
) {
}
