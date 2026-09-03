package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class ListingBoundaryMigrationTest {

    @Test
    void migrationAddsAuditableListingBoundariesWithoutDeletingHistoricalCandles() throws IOException {
        String migration = migrationText();

        assertThat(migration).contains("ADD COLUMN listed_on DATE");
        assertThat(migration).contains("ADD COLUMN listing_date_source_url TEXT");
        assertThat(migration).contains("ADD COLUMN details TEXT");
        assertThat(migration).contains("symbol = 'ANGELONE'");
        assertThat(migration).contains("DATE '2020-10-05'");
        assertThat(migration).contains("symbol = '360ONE'");
        assertThat(migration).contains("DATE '2019-09-19'");
        assertThat(migration).contains("uk_market_data_quality_issue_open_chunk_code");
        assertThat(migration).doesNotContain("DELETE FROM market_candle");
        assertThat(migration).doesNotContain("UPDATE market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V9__add_listing_boundaries_and_normalization_audit.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
