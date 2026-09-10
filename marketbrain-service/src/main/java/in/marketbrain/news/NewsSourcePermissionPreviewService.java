package in.marketbrain.news;

import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URISyntaxException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

@Service
public class NewsSourcePermissionPreviewService {

    static final String CONTRACT_VERSION = "NEWS_SOURCE_PERMISSION_V1";
    private static final int MAXIMUM_SOURCES = 100;
    private static final int MAXIMUM_RETENTION_DAYS = 3650;

    private final NewsSourcePermissionManifestHasher manifestHasher;

    public NewsSourcePermissionPreviewService(NewsSourcePermissionManifestHasher manifestHasher) {
        this.manifestHasher = manifestHasher;
    }

    public NewsSourcePermissionPreview preview(NewsSourcePermissionPreviewRequest request) {
        validateRequest(request);
        String preparedBy = request.preparedBy().trim();
        List<NewsSourcePermissionItemPreview> sources = request.sources().stream()
                .map(this::validateAndMap)
                .sorted(Comparator.comparing(NewsSourcePermissionItemPreview::sourceKey))
                .toList();
        ensureUniqueKeys(sources);

        int awaiting = count(sources, NewsSourcePermissionStatus.AWAITING_RESPONSE);
        int termsReview = count(sources, NewsSourcePermissionStatus.TERMS_REVIEW_REQUIRED);
        int approved = count(sources, NewsSourcePermissionStatus.APPROVED);
        int rejected = count(sources, NewsSourcePermissionStatus.REJECTED);
        int permissionComplete = (int) sources.stream()
                .filter(NewsSourcePermissionItemPreview::permissionComplete).count();
        int eligible = (int) sources.stream()
                .filter(NewsSourcePermissionItemPreview::integrationEligible).count();
        int enabled = (int) sources.stream()
                .filter(NewsSourcePermissionItemPreview::integrationEnabled).count();
        List<String> failures = new ArrayList<>();
        if (enabled != 0) {
            failures.add("INTEGRATIONS_MUST_REMAIN_DISABLED");
        }
        boolean persistenceReady = failures.isEmpty();
        String manifestHash = manifestHasher.hash(request.preparedOn(), preparedBy, sources);

        return new NewsSourcePermissionPreview(
                persistenceReady ? "REVIEW_REQUIRED" : "BLOCKED",
                CONTRACT_VERSION,
                request.preparedOn(),
                preparedBy,
                sources.size(),
                awaiting,
                termsReview,
                approved,
                rejected,
                permissionComplete,
                eligible,
                enabled,
                persistenceReady,
                false,
                manifestHash,
                false,
                0,
                0,
                0,
                0,
                0,
                0,
                List.copyOf(failures),
                sources,
                "The permission register is structurally ready for review; every news integration remains disabled."
        );
    }

    private void validateRequest(NewsSourcePermissionPreviewRequest request) {
        if (request == null) {
            throw new IllegalArgumentException("A permission preview request is required.");
        }
        if (request.preparedOn() == null) {
            throw new IllegalArgumentException("preparedOn is required.");
        }
        requireText(request.preparedBy(), "preparedBy");
        if (request.sources() == null || request.sources().isEmpty()) {
            throw new IllegalArgumentException("At least one source permission is required.");
        }
        if (request.sources().size() > MAXIMUM_SOURCES) {
            throw new IllegalArgumentException("A permission preview cannot contain more than 100 sources.");
        }
    }

    private NewsSourcePermissionItemPreview validateAndMap(NewsSourcePermissionDraft source) {
        if (source == null) {
            throw new IllegalArgumentException("Source permissions cannot contain null entries.");
        }
        String sourceKey = normalizeKey(source.sourceKey());
        String displayName = requireText(source.displayName(), "displayName");
        if (source.sourceType() == null) {
            throw new IllegalArgumentException(sourceKey + ": sourceType is required.");
        }
        if (source.permissionStatus() == null) {
            throw new IllegalArgumentException(sourceKey + ": permissionStatus is required.");
        }
        String sourceUrl = validateHttpsUrl(source.sourceUrl(), sourceKey);
        String evidence = requireText(source.permissionEvidenceReference(),
                sourceKey + ": permissionEvidenceReference");
        List<String> permittedFields = normalizeFields(source.permittedFields(), sourceKey);
        validateDatesAndRules(source, sourceKey, permittedFields);

        boolean approvedForUse = approvedForUse(source.permissionStatus());
        boolean complete = approvedForUse
                || source.permissionStatus() == NewsSourcePermissionStatus.REJECTED
                || source.permissionStatus() == NewsSourcePermissionStatus.PAID_ONLY;
        boolean eligible = approvedForUse
                && source.decidedOn() != null
                && source.retentionDays() != null
                && !permittedFields.isEmpty();
        String detail = switch (source.permissionStatus()) {
            case AWAITING_RESPONSE -> "A written response is pending; ingestion is prohibited.";
            case TERMS_REVIEW_REQUIRED -> "Published terms require review; ingestion is prohibited.";
            case APPROVED -> eligible
                    ? "The written approval is complete but integration still requires a separate activation review."
                    : "The written approval record is incomplete; ingestion is prohibited.";
            case API_LICENSE_ACCEPTED -> eligible
                    ? "The API licence is accepted but integration still requires a separate activation review."
                    : "The API licence record is incomplete; ingestion is prohibited.";
            case PUBLIC_TERMS_ALLOWED -> eligible
                    ? "The public terms allow the recorded use but integration still requires a separate activation review."
                    : "The public-terms record is incomplete; ingestion is prohibited.";
            case REJECTED -> "Permission was rejected; ingestion is prohibited.";
            case PAID_ONLY -> "The source requires a paid licence; ingestion is prohibited until subscribed.";
        };

        return new NewsSourcePermissionItemPreview(
                sourceKey,
                displayName,
                source.sourceType(),
                source.permissionStatus(),
                sourceUrl,
                evidence,
                source.requestedOn(),
                source.decidedOn(),
                source.retentionDays(),
                source.headlineStorageAllowed(),
                source.snippetStorageAllowed(),
                source.fullTextStorageAllowed(),
                source.localAiProcessingAllowed(),
                source.derivedDataRetentionAllowed(),
                source.attributionRequired(),
                permittedFields,
                complete,
                eligible,
                false,
                detail
        );
    }

    private void validateDatesAndRules(
            NewsSourcePermissionDraft source,
            String sourceKey,
            List<String> permittedFields
    ) {
        if (source.requestedOn() != null && source.decidedOn() != null
                && source.decidedOn().isBefore(source.requestedOn())) {
            throw new IllegalArgumentException(sourceKey + ": decidedOn cannot precede requestedOn.");
        }
        if (source.retentionDays() != null
                && (source.retentionDays() < 0 || source.retentionDays() > MAXIMUM_RETENTION_DAYS)) {
            throw new IllegalArgumentException(sourceKey + ": retentionDays must be between 0 and 3650.");
        }
        if (source.permissionStatus() == NewsSourcePermissionStatus.AWAITING_RESPONSE
                && source.requestedOn() == null) {
            throw new IllegalArgumentException(sourceKey + ": requestedOn is required while awaiting a response.");
        }
        if (source.permissionStatus() == NewsSourcePermissionStatus.TERMS_REVIEW_REQUIRED
                && source.requestedOn() != null) {
            throw new IllegalArgumentException(sourceKey + ": requestedOn must be empty until a request is sent.");
        }
        if (approvedForUse(source.permissionStatus())) {
            if (source.decidedOn() == null || source.retentionDays() == null || permittedFields.isEmpty()) {
                throw new IllegalArgumentException(sourceKey
                        + ": an approved or accepted permission needs decidedOn, retentionDays, and permittedFields.");
            }
        } else if (source.headlineStorageAllowed()
                || source.snippetStorageAllowed()
                || source.fullTextStorageAllowed()
                || source.localAiProcessingAllowed()
                || source.derivedDataRetentionAllowed()
                || source.retentionDays() != null
                || !permittedFields.isEmpty()) {
            throw new IllegalArgumentException(sourceKey
                    + ": usage rights cannot be recorded until permission is approved.");
        }
        if (source.fullTextStorageAllowed() && !permittedFields.contains("FULL_TEXT")) {
            throw new IllegalArgumentException(sourceKey
                    + ": FULL_TEXT must be listed when full-text storage is allowed.");
        }
    }

    private List<String> normalizeFields(List<String> fields, String sourceKey) {
        if (fields == null) {
            return List.of();
        }
        List<String> normalized = fields.stream()
                .map(field -> requireText(field, sourceKey + ": permittedFields entry")
                        .trim().toUpperCase(Locale.ROOT))
                .distinct()
                .sorted()
                .toList();
        if (normalized.size() != fields.size()) {
            throw new IllegalArgumentException(sourceKey + ": permittedFields must be unique.");
        }
        return normalized;
    }

    private void ensureUniqueKeys(List<NewsSourcePermissionItemPreview> sources) {
        Set<String> keys = new HashSet<>();
        for (NewsSourcePermissionItemPreview source : sources) {
            if (!keys.add(source.sourceKey())) {
                throw new IllegalArgumentException("Duplicate sourceKey: " + source.sourceKey());
            }
        }
    }

    private int count(List<NewsSourcePermissionItemPreview> sources, NewsSourcePermissionStatus status) {
        return (int) sources.stream().filter(source -> source.permissionStatus() == status).count();
    }

    private boolean approvedForUse(NewsSourcePermissionStatus status) {
        return status == NewsSourcePermissionStatus.APPROVED
                || status == NewsSourcePermissionStatus.API_LICENSE_ACCEPTED
                || status == NewsSourcePermissionStatus.PUBLIC_TERMS_ALLOWED;
    }

    private String normalizeKey(String value) {
        String key = requireText(value, "sourceKey").trim().toUpperCase(Locale.ROOT);
        if (!key.matches("^[A-Z0-9_]{3,64}$")) {
            throw new IllegalArgumentException(
                    "sourceKey must contain 3-64 uppercase letters, digits, or underscores.");
        }
        return key;
    }

    private String validateHttpsUrl(String value, String sourceKey) {
        String url = requireText(value, sourceKey + ": sourceUrl");
        try {
            URI uri = new URI(url);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
                throw new IllegalArgumentException(sourceKey + ": sourceUrl must be an absolute HTTPS URL.");
            }
            return uri.toString();
        } catch (URISyntaxException exception) {
            throw new IllegalArgumentException(sourceKey + ": sourceUrl must be an absolute HTTPS URL.");
        }
    }

    private String requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required.");
        }
        return value.trim();
    }
}
