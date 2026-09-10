package in.marketbrain.news;

public record NewsSourcePermissionRecord(
        String sourceKey,
        String permissionStatus,
        boolean integrationEnabled,
        Integer retentionDays,
        boolean headlineStorageAllowed,
        boolean snippetStorageAllowed,
        boolean localAiProcessingAllowed,
        boolean derivedDataRetentionAllowed,
        boolean attributionRequired
) {
}
