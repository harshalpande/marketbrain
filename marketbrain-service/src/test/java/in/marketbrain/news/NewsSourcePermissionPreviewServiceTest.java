package in.marketbrain.news;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class NewsSourcePermissionPreviewServiceTest {

    private final NewsSourcePermissionPreviewService service =
            new NewsSourcePermissionPreviewService(new NewsSourcePermissionManifestHasher());

    @Test
    void previewsPendingAndTermsReviewSourcesWithoutEnablingIngestion() {
        NewsSourcePermissionPreview preview = service.preview(new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9),
                "Harshal Pande",
                List.of(
                        pending("MARKETAUX_API", "Marketaux", NewsSourceType.NEWS_API),
                        termsReview("NSE_DISCLOSURES", "NSE corporate disclosures")
                )));

        assertThat(preview.status()).isEqualTo("REVIEW_REQUIRED");
        assertThat(preview.permissionContractVersion()).isEqualTo("NEWS_SOURCE_PERMISSION_V1");
        assertThat(preview.sourceCount()).isEqualTo(2);
        assertThat(preview.awaitingResponseCount()).isOne();
        assertThat(preview.termsReviewRequiredCount()).isOne();
        assertThat(preview.approvedCount()).isZero();
        assertThat(preview.integrationEligibleCount()).isZero();
        assertThat(preview.integrationEnabledCount()).isZero();
        assertThat(preview.registerPersistenceReady()).isTrue();
        assertThat(preview.contentIngestionAllowed()).isFalse();
        assertThat(preview.databaseWritesPerformed()).isFalse();
        assertThat(preview.providerRequestCount()).isZero();
        assertThat(preview.articlesStored()).isZero();
        assertThat(preview.ollamaCallCount()).isZero();
        assertThat(preview.signalsCreated()).isZero();
        assertThat(preview.ordersCreated()).isZero();
        assertThat(preview.manifestHash()).matches("^[0-9a-f]{64}$");
        assertThat(preview.sources()).extracting(NewsSourcePermissionItemPreview::sourceKey)
                .containsExactly("MARKETAUX_API", "NSE_DISCLOSURES");
        assertThat(preview.sources()).allMatch(source -> !source.integrationEnabled());
    }

    @Test
    void manifestIsIndependentOfInputOrderAndFieldOrder() {
        NewsSourcePermissionDraft first = approved("APPROVED_SOURCE", List.of("URL", "HEADLINE"));
        NewsSourcePermissionDraft second = pending("PENDING_SOURCE", "Pending", NewsSourceType.RSS);

        NewsSourcePermissionPreview ordered = service.preview(new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9), "Reviewer", List.of(first, second)));
        NewsSourcePermissionPreview reversed = service.preview(new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9), "Reviewer",
                List.of(second, approved("APPROVED_SOURCE", List.of("HEADLINE", "URL")))));

        assertThat(reversed.manifestHash()).isEqualTo(ordered.manifestHash());
        assertThat(ordered.approvedCount()).isOne();
        assertThat(ordered.permissionCompleteCount()).isOne();
        assertThat(ordered.integrationEligibleCount()).isOne();
        assertThat(ordered.integrationEnabledCount()).isZero();
        assertThat(ordered.contentIngestionAllowed()).isFalse();
    }

    @Test
    void refusesUsageRightsWhileResponseIsPending() {
        NewsSourcePermissionDraft unsafe = new NewsSourcePermissionDraft(
                "PENDING_SOURCE", "Pending", NewsSourceType.RSS,
                NewsSourcePermissionStatus.AWAITING_RESPONSE,
                "https://example.test/rss", "EMAIL_SENT", LocalDate.of(2026, 9, 9), null,
                365, true, false, false, false, false, true, List.of("HEADLINE"));

        assertThatThrownBy(() -> service.preview(new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9), "Reviewer", List.of(unsafe))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("usage rights cannot be recorded");
    }

    @Test
    void refusesDuplicateSourceKeysAfterCanonicalization() {
        assertThatThrownBy(() -> service.preview(new NewsSourcePermissionPreviewRequest(
                LocalDate.of(2026, 9, 9), "Reviewer",
                List.of(
                        pending("marketaux_api", "Marketaux", NewsSourceType.NEWS_API),
                        pending("MARKETAUX_API", "Marketaux duplicate", NewsSourceType.NEWS_API)
                ))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Duplicate sourceKey");
    }

    private NewsSourcePermissionDraft pending(String key, String name, NewsSourceType type) {
        return new NewsSourcePermissionDraft(
                key, name, type, NewsSourcePermissionStatus.AWAITING_RESPONSE,
                "https://example.test/source", "EMAIL_SENT", LocalDate.of(2026, 9, 9), null,
                null, false, false, false, false, false, false, List.of());
    }

    private NewsSourcePermissionDraft termsReview(String key, String name) {
        return new NewsSourcePermissionDraft(
                key, name, NewsSourceType.OFFICIAL_DISCLOSURE,
                NewsSourcePermissionStatus.TERMS_REVIEW_REQUIRED,
                "https://example.test/terms", "PUBLISHED_TERMS", null, null,
                null, false, false, false, false, false, false, List.of());
    }

    private NewsSourcePermissionDraft approved(String key, List<String> fields) {
        return new NewsSourcePermissionDraft(
                key, "Approved", NewsSourceType.RSS, NewsSourcePermissionStatus.APPROVED,
                "https://example.test/rss", "WRITTEN_APPROVAL",
                LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 2), 365,
                true, false, false, true, true, true, fields);
    }
}
