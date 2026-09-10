package in.marketbrain.news;

public record NewsSourceRunResult(
        String sourceKey,
        String status,
        int providerRequestCount,
        int candidateCount,
        int storedArticleCount,
        String detail
) {
}
