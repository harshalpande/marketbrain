package in.marketbrain.news;

import in.marketbrain.configuration.NewsProperties;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class NewsIngestionRunServiceTest {

    private final NewsSourcePermissionRepository permissionRepository = mock(NewsSourcePermissionRepository.class);
    private final NewsArticleRepository articleRepository = mock(NewsArticleRepository.class);
    private final NewsConnector connector = mock(NewsConnector.class);

    @Test
    void skipsEverySourceWithoutCallingProvidersWhenGlobalGatesAreDisabled() {
        when(permissionRepository.recordsBySourceKey()).thenReturn(Map.of(
                "MARKETAUX_API", pending("MARKETAUX_API")
        ));
        when(connector.integrationType()).thenReturn(NewsSourceIntegrationType.MARKETAUX_API);
        var service = new NewsIngestionRunService(
                new NewsProperties(false, false, 100, 20,
                        new NewsProperties.Marketaux("https://api.marketaux.com/v1/news/all", "")),
                new NewsSourceCatalog(),
                permissionRepository,
                articleRepository,
                java.util.List.of(connector));

        NewsIngestionRunResult result = service.runOnce(null);

        assertThat(result.status()).isEqualTo("BLOCKED_BY_GOVERNANCE");
        assertThat(result.sourceCount()).isEqualTo(8);
        assertThat(result.attemptedSourceCount()).isZero();
        assertThat(result.providerRequestCount()).isZero();
        assertThat(result.candidateArticleCount()).isZero();
        assertThat(result.storedArticleCount()).isZero();
        assertThat(result.signalsCreated()).isZero();
        assertThat(result.ordersCreated()).isZero();
        verify(connector, never()).fetch(org.mockito.ArgumentMatchers.any());
        verifyNoInteractions(articleRepository);
    }

    private NewsSourcePermissionRecord pending(String sourceKey) {
        return new NewsSourcePermissionRecord(sourceKey, "AWAITING_RESPONSE", false,
                null, false, false, false, false, false);
    }
}
