package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class ListingBoundaryEvidenceMigrationTest {

    @Test
    void migrationPreservesRawEvidenceAndCannotModifyCandles() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V13__create_listing_boundary_evidence.sql")) {
            assertThat(stream).isNotNull();
            String migration = new String(stream.readAllBytes(), StandardCharsets.UTF_8);

            assertThat(migration).contains("CREATE TABLE instrument_listing_evidence");
            assertThat(migration).contains("reported_listed_on DATE NOT NULL");
            assertThat(migration).contains("provider_prelisting_candle_on DATE");
            assertThat(migration).contains("EARLIER_PROVIDER_HISTORY");
            assertThat(migration).contains("uk_listing_evidence_file");
            assertThat(migration).doesNotContain("DELETE FROM market_candle");
            assertThat(migration).doesNotContain("UPDATE market_candle");
        }
    }
}
