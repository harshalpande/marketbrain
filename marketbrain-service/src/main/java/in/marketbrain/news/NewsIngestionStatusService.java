package in.marketbrain.news;

import in.marketbrain.configuration.NewsProperties;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.function.Function;

@Service
class NewsIngestionStatusService {

    private static final Set<String> FETCH_ALLOWED_PERMISSION_STATUSES = Set.of(
            "APPROVED",
            "API_LICENSE_ACCEPTED",
            "PUBLIC_TERMS_ALLOWED"
    );

    private final NewsProperties properties;
    private final NewsSourceCatalog catalog;
    private final NewsSourcePermissionRepository permissionRepository;
    private final List<NewsConnector> connectors;

    NewsIngestionStatusService(
            NewsProperties properties,
            NewsSourceCatalog catalog,
            NewsSourcePermissionRepository permissionRepository,
            List<NewsConnector> connectors
    ) {
        this.properties = properties;
        this.catalog = catalog;
        this.permissionRepository = permissionRepository;
        this.connectors = connectors;
    }

    NewsIngestionStatus status() {
        Map<String, NewsSourcePermissionRecord> records = permissionRepository.recordsBySourceKey();
        Map<NewsSourceIntegrationType, NewsConnector> connectorByType = connectors.stream()
                .collect(Collectors.toUnmodifiableMap(NewsConnector::integrationType, Function.identity()));
        List<NewsIngestionSourceStatus> sources = catalog.plannedSources().stream()
                .map(source -> statusFor(source, records.get(source.sourceKey()), connectorByType))
                .toList();

        int implemented = (int) sources.stream().filter(NewsIngestionSourceStatus::connectorImplemented).count();
        int persisted = (int) sources.stream().filter(NewsIngestionSourceStatus::persisted).count();
        int enabled = (int) sources.stream().filter(NewsIngestionSourceStatus::integrationEnabled).count();
        int eligible = (int) sources.stream().filter(NewsIngestionSourceStatus::liveFetchEligible).count();
        String status = eligible > 0 ? "READY_FOR_GOVERNED_FETCH" : "BLOCKED_BY_GOVERNANCE";
        String detail = eligible > 0
                ? "At least one source can be fetched under the current global and source-level gates."
                : "Connectors are implemented, but no source can be fetched under the current gates.";

        return new NewsIngestionStatus(
                status,
                properties.enabled(),
                properties.liveFetchEnabled(),
                properties.maximumArticlesPerDay(),
                sources.size(),
                implemented,
                persisted,
                enabled,
                eligible,
                0,
                0,
                0,
                0,
                0,
                0,
                sources,
                detail);
    }

    private NewsIngestionSourceStatus statusFor(
            NewsSourceDefinition source,
            NewsSourcePermissionRecord record,
            Map<NewsSourceIntegrationType, NewsConnector> connectorByType
    ) {
        NewsConnector connector = connectorByType.get(source.integrationType());
        boolean connectorImplemented = connector != null;
        boolean liveFetchCapable = connectorImplemented && connector.liveFetchCapable();
        boolean persisted = record != null;
        boolean integrationEnabled = record != null && record.integrationEnabled();
        String permissionStatus = record == null ? "NOT_PERSISTED" : record.permissionStatus();
        String blockedReason = blockedReason(
                connectorImplemented,
                liveFetchCapable,
                persisted,
                integrationEnabled,
                permissionStatus);
        return new NewsIngestionSourceStatus(
                source.sourceKey(),
                source.displayName(),
                source.sourceType(),
                source.integrationType(),
                permissionStatus,
                connectorImplemented,
                persisted,
                integrationEnabled,
                blockedReason == null,
                blockedReason,
                source.note());
    }

    private String blockedReason(
            boolean connectorImplemented,
            boolean liveFetchCapable,
            boolean persisted,
            boolean integrationEnabled,
            String permissionStatus
    ) {
        if (!properties.enabled()) {
            return "NEWS_MODULE_DISABLED";
        }
        if (!properties.liveFetchEnabled()) {
            return "LIVE_FETCH_DISABLED";
        }
        if (!connectorImplemented) {
            return "CONNECTOR_NOT_IMPLEMENTED";
        }
        if (!liveFetchCapable) {
            return "SOURCE_SPECIFIC_EXTRACTOR_PENDING";
        }
        if (!persisted) {
            return "PERMISSION_RECORD_MISSING";
        }
        if (!integrationEnabled) {
            return "SOURCE_INTEGRATION_DISABLED";
        }
        if (!FETCH_ALLOWED_PERMISSION_STATUSES.contains(permissionStatus)) {
            return "PERMISSION_NOT_APPROVED";
        }
        return null;
    }
}
