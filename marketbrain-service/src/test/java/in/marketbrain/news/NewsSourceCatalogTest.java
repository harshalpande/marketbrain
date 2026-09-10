package in.marketbrain.news;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class NewsSourceCatalogTest {

    private final NewsSourceCatalog catalog = new NewsSourceCatalog();

    @Test
    void declaresAllReviewedNewsSourcesWithConnectors() {
        var sources = catalog.plannedSources();

        assertThat(sources).hasSize(8);
        assertThat(sources).extracting(NewsSourceDefinition::sourceKey)
                .containsExactly(
                        "MARKETAUX_API",
                        "ECONOMIC_TIMES_RSS",
                        "LIVEMINT_RSS",
                        "BUSINESS_STANDARD_RSS",
                        "NSE_DISCLOSURES",
                        "BSE_DISCLOSURES",
                        "SEBI_PUBLIC_UPDATES",
                        "RBI_PRESS_RELEASES");
        assertThat(sources).extracting(NewsSourceDefinition::integrationType)
                .contains(
                        NewsSourceIntegrationType.MARKETAUX_API,
                        NewsSourceIntegrationType.RSS_FEED,
                        NewsSourceIntegrationType.OFFICIAL_EVENTS);
        assertThat(sources).allMatch(source -> source.sourceUrl().startsWith("https://"));
    }
}
