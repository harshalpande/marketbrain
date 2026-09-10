package in.marketbrain.news;

public record NewsIngestionSourceStatus(
        String sourceKey,
        String displayName,
        NewsSourceType sourceType,
        NewsSourceIntegrationType integrationType,
        String permissionStatus,
        boolean connectorImplemented,
        boolean persisted,
        boolean integrationEnabled,
        boolean liveFetchEligible,
        String blockedReason,
        String note
) {
}
