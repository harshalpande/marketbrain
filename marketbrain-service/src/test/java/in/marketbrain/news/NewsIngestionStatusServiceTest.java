package in.marketbrain.news;

import in.marketbrain.configuration.NewsProperties;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class NewsIngestionStatusServiceTest {

    private final NewsSourcePermissionRepository repository = mock(NewsSourcePermissionRepository.class);

    @Test
    void reportsImplementedSourcesButBlocksProviderRequestsByDefault() {
        when(repository.recordsBySourceKey()).thenReturn(Map.of(
                "MARKETAUX_API", pending("MARKETAUX_API"),
                "ECONOMIC_TIMES_RSS", pending("ECONOMIC_TIMES_RSS"),
                "LIVEMINT_RSS", pending("LIVEMINT_RSS"),
                "BUSINESS_STANDARD_RSS", pending("BUSINESS_STANDARD_RSS"),
                "NSE_DISCLOSURES", termsReview("NSE_DISCLOSURES"),
                "BSE_DISCLOSURES", termsReview("BSE_DISCLOSURES"),
                "SEBI_PUBLIC_UPDATES", termsReview("SEBI_PUBLIC_UPDATES"),
                "RBI_PRESS_RELEASES", termsReview("RBI_PRESS_RELEASES")
        ));
        var service = new NewsIngestionStatusService(
                new NewsProperties(false, false, 100, 20,
                        new NewsProperties.Marketaux("https://api.marketaux.com/v1/news/all", "")),
                new NewsSourceCatalog(),
                repository,
                java.util.List.of(
                        new ConnectorStub(NewsSourceIntegrationType.MARKETAUX_API),
                        new ConnectorStub(NewsSourceIntegrationType.RSS_FEED),
                        new ConnectorStub(NewsSourceIntegrationType.OFFICIAL_EVENTS)));

        NewsIngestionStatus status = service.status();

        assertThat(status.status()).isEqualTo("BLOCKED_BY_GOVERNANCE");
        assertThat(status.sourceCount()).isEqualTo(8);
        assertThat(status.persistedSourceCount()).isEqualTo(8);
        assertThat(status.enabledSourceCount()).isZero();
        assertThat(status.liveFetchEligibleCount()).isZero();
        assertThat(status.providerRequestCount()).isZero();
        assertThat(status.articlesStored()).isZero();
        assertThat(status.ollamaCallCount()).isZero();
        assertThat(status.signalsCreated()).isZero();
        assertThat(status.ordersCreated()).isZero();
        assertThat(status.sources()).allMatch(source -> "NEWS_MODULE_DISABLED".equals(source.blockedReason()));
    }

    private NewsSourcePermissionRecord pending(String sourceKey) {
        return new NewsSourcePermissionRecord(sourceKey, "AWAITING_RESPONSE", false,
                null, false, false, false, false, false);
    }

    private NewsSourcePermissionRecord termsReview(String sourceKey) {
        return new NewsSourcePermissionRecord(sourceKey, "TERMS_REVIEW_REQUIRED", false,
                null, false, false, false, false, false);
    }

    private record ConnectorStub(NewsSourceIntegrationType integrationType) implements NewsConnector {
        @Override
        public NewsFetchResult fetch(NewsFetchRequest request) {
            return NewsFetchResult.skipped(request.source().sourceKey(), "test");
        }
    }
}
