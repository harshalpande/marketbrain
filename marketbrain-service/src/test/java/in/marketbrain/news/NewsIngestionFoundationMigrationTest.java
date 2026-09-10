package in.marketbrain.news;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class NewsIngestionFoundationMigrationTest {

    @Test
    void migrationCreatesPermissionGatedNewsFoundationWithoutTradingSideEffects() throws IOException {
        try (var stream = getClass().getResourceAsStream(
                "/db/migration/V23__create_news_ingestion_foundation.sql")) {
            assertThat(stream).isNotNull();
            String sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            assertThat(sql).contains("CREATE TABLE news_source_permission_register");
            assertThat(sql).contains("CREATE TABLE news_source_checkpoint");
            assertThat(sql).contains("CREATE TABLE news_article");
            assertThat(sql).contains("CREATE TABLE news_article_instrument_match");
            assertThat(sql).contains("CREATE TABLE news_event_feature");
            assertThat(sql).contains("ck_news_integration_requires_permission");
            assertThat(sql).contains("integration_enabled = FALSE");
            assertThat(sql).contains("'MARKETAUX_API'");
            assertThat(sql).contains("'ECONOMIC_TIMES_RSS'");
            assertThat(sql).contains("'LIVEMINT_RSS'");
            assertThat(sql).contains("'BUSINESS_STANDARD_RSS'");
            assertThat(sql).contains("'NSE_DISCLOSURES'");
            assertThat(sql).contains("'BSE_DISCLOSURES'");
            assertThat(sql).contains("'SEBI_PUBLIC_UPDATES'");
            assertThat(sql).contains("'RBI_PRESS_RELEASES'");
            assertThat(sql).doesNotContain("INSERT INTO market_signal");
            assertThat(sql).doesNotContain("INSERT INTO paper_order");
            assertThat(sql).doesNotContain("INSERT INTO paper_fill");
        }
    }
}
