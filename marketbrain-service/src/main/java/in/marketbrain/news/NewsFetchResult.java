package in.marketbrain.news;

import java.util.List;

public record NewsFetchResult(
        String sourceKey,
        String status,
        int providerRequestCount,
        List<NewsArticleCandidate> articles,
        String detail
) {
    public static NewsFetchResult skipped(String sourceKey, String detail) {
        return new NewsFetchResult(sourceKey, "SKIPPED", 0, List.of(), detail);
    }
}
