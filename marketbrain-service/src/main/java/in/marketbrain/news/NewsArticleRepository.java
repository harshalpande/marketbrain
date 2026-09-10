package in.marketbrain.news;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

@Repository
class NewsArticleRepository {

    private final JdbcClient jdbc;
    private final NewsArticleHasher hasher;

    NewsArticleRepository(JdbcClient jdbc, NewsArticleHasher hasher) {
        this.jdbc = jdbc;
        this.hasher = hasher;
    }

    int saveCandidates(NewsSourcePermissionRecord permission, List<NewsArticleCandidate> candidates) {
        int stored = 0;
        for (NewsArticleCandidate candidate : candidates) {
            stored += saveCandidate(permission, candidate);
        }
        return stored;
    }

    private int saveCandidate(NewsSourcePermissionRecord permission, NewsArticleCandidate candidate) {
        String publishedAt = candidate.providerPublishedAt() == null
                ? ""
                : candidate.providerPublishedAt().toString();
        String contentHash = hasher.contentHash(
                candidate.sourceKey(),
                candidate.canonicalUrl(),
                candidate.title(),
                publishedAt);
        Instant expiresAt = permission.retentionDays() == null
                ? null
                : Instant.now().plus(permission.retentionDays(), ChronoUnit.DAYS);

        return jdbc.sql("""
                        INSERT INTO news_article (
                            id,
                            source_key,
                            provider_item_id,
                            canonical_url,
                            source_domain,
                            title,
                            snippet,
                            provider_published_at,
                            content_hash,
                            expires_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT DO NOTHING
                        """)
                .params(
                        UUID.randomUUID(),
                        permission.sourceKey(),
                        candidate.providerItemId(),
                        candidate.canonicalUrl(),
                        candidate.sourceDomain(),
                        permission.headlineStorageAllowed() ? candidate.title() : null,
                        permission.snippetStorageAllowed() ? candidate.snippet() : null,
                        timestamp(candidate.providerPublishedAt()),
                        contentHash,
                        timestamp(expiresAt))
                .update();
    }

    private Timestamp timestamp(Instant instant) {
        return instant == null ? null : Timestamp.from(instant);
    }
}
