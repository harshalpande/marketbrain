package in.marketbrain.news;

public record NewsSourceDefinition(
        String sourceKey,
        String displayName,
        NewsSourceType sourceType,
        NewsSourceIntegrationType integrationType,
        String sourceUrl,
        String note
) {
}
