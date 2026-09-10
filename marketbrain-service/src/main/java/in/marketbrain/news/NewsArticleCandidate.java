package in.marketbrain.news;

import java.time.Instant;
import java.util.List;

public record NewsArticleCandidate(
        String sourceKey,
        String providerItemId,
        String canonicalUrl,
        String sourceDomain,
        String title,
        String snippet,
        Instant providerPublishedAt,
        List<NewsEntityCandidate> entities
) {
}
