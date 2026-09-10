package in.marketbrain.news;

import in.marketbrain.configuration.NewsProperties;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
class NewsIngestionRunService {

    private static final Set<String> FETCH_ALLOWED_PERMISSION_STATUSES = Set.of(
            "APPROVED",
            "API_LICENSE_ACCEPTED",
            "PUBLIC_TERMS_ALLOWED"
    );

    private final NewsProperties properties;
    private final NewsSourceCatalog catalog;
    private final NewsSourcePermissionRepository permissionRepository;
    private final NewsArticleRepository articleRepository;
    private final Map<NewsSourceIntegrationType, NewsConnector> connectors;

    NewsIngestionRunService(
            NewsProperties properties,
            NewsSourceCatalog catalog,
            NewsSourcePermissionRepository permissionRepository,
            NewsArticleRepository articleRepository,
            List<NewsConnector> connectors
    ) {
        this.properties = properties;
        this.catalog = catalog;
        this.permissionRepository = permissionRepository;
        this.articleRepository = articleRepository;
        this.connectors = connectors.stream()
                .collect(Collectors.toUnmodifiableMap(NewsConnector::integrationType, Function.identity()));
    }

    NewsIngestionRunResult runOnce(UUID runId) {
        UUID effectiveRunId = runId == null ? UUID.randomUUID() : runId;
        Map<String, NewsSourcePermissionRecord> permissions = permissionRepository.recordsBySourceKey();
        List<NewsSourceRunResult> results = catalog.plannedSources().stream()
                .map(source -> runSource(source, permissions.get(source.sourceKey())))
                .toList();

        int attemptedSources = (int) results.stream()
                .filter(result -> result.providerRequestCount() > 0)
                .count();
        int providerRequests = results.stream().mapToInt(NewsSourceRunResult::providerRequestCount).sum();
        int candidates = results.stream().mapToInt(NewsSourceRunResult::candidateCount).sum();
        int stored = results.stream().mapToInt(NewsSourceRunResult::storedArticleCount).sum();
        String status = providerRequests == 0 ? "BLOCKED_BY_GOVERNANCE" : "COMPLETED";
        String detail = providerRequests == 0
                ? "No source passed every global, permission, and source-level gate; no provider was contacted."
                : "Governed news ingestion completed for the currently enabled sources.";

        return new NewsIngestionRunResult(
                status,
                effectiveRunId,
                properties.enabled(),
                properties.liveFetchEnabled(),
                results.size(),
                attemptedSources,
                providerRequests,
                candidates,
                stored,
                0,
                0,
                0,
                0,
                results,
                detail);
    }

    private NewsSourceRunResult runSource(NewsSourceDefinition source, NewsSourcePermissionRecord permission) {
        String blockedReason = blockedReason(source, permission);
        if (blockedReason != null) {
            return new NewsSourceRunResult(source.sourceKey(), "SKIPPED", 0, 0, 0, blockedReason);
        }
        NewsConnector connector = connectors.get(source.integrationType());
        NewsFetchResult fetchResult = connector.fetch(new NewsFetchRequest(
                source,
                properties.maximumArticlesPerDay()));
        int stored = articleRepository.saveCandidates(permission, fetchResult.articles());
        return new NewsSourceRunResult(
                source.sourceKey(),
                fetchResult.status(),
                fetchResult.providerRequestCount(),
                fetchResult.articles().size(),
                stored,
                fetchResult.detail());
    }

    private String blockedReason(NewsSourceDefinition source, NewsSourcePermissionRecord permission) {
        if (!properties.enabled()) {
            return "NEWS_MODULE_DISABLED";
        }
        if (!properties.liveFetchEnabled()) {
            return "LIVE_FETCH_DISABLED";
        }
        if (!connectors.containsKey(source.integrationType())) {
            return "CONNECTOR_NOT_IMPLEMENTED";
        }
        if (!connectors.get(source.integrationType()).liveFetchCapable()) {
            return "SOURCE_SPECIFIC_EXTRACTOR_PENDING";
        }
        if (permission == null) {
            return "PERMISSION_RECORD_MISSING";
        }
        if (!permission.integrationEnabled()) {
            return "SOURCE_INTEGRATION_DISABLED";
        }
        if (!FETCH_ALLOWED_PERMISSION_STATUSES.contains(permission.permissionStatus())) {
            return "PERMISSION_NOT_APPROVED";
        }
        return null;
    }
}
