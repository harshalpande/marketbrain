package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class Batch4IdentityAliasMigrationTest {

    @Test
    void migrationAddsOnlyTheSevenReviewedExactDateAliases() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V15__add_reviewed_batch4_identity_aliases.sql")) {
            assertThat(stream).isNotNull();
            String migration = new String(stream.readAllBytes(), StandardCharsets.UTF_8);

            assertThat(migration).contains("'NAVA', 'NBVENTURES', 'INE725A01022'");
            assertThat(migration).contains("'SHRIRAMFIN', 'SRTRANSFIN', 'INE721A01013'");
            assertThat(migration).contains("'UNITDSPR', 'MCDOWELL-N', 'INE854D01016'");
            assertThat(migration).contains("'UNOMINDA', 'MINDAIND', 'INE405E01015'");
            assertThat(migration).contains("DATE '2014-05-21', DATE '2014-05-21'");
            assertThat(migration).contains("DATE '2020-06-18', DATE '2020-06-18'");
            assertThat(migration).contains("DATE '2020-03-23', DATE '2020-03-23'");
            assertThat(migration).contains("DATE '2012-11-12', DATE '2012-11-12'");
            assertThat(migration).contains("DATE '2013-11-28', DATE '2013-11-28'");
            assertThat(migration).contains("DATE '2014-06-30', DATE '2014-06-30'");
            assertThat(migration).contains("DATE '2014-09-15', DATE '2014-09-15'");
            assertThat(migration).contains("The alias is limited to that reviewed date.");
            assertThat(migration.lines()
                    .filter(line -> line.stripLeading().startsWith("('NSE'"))
                    .count()).isEqualTo(7);
            assertThat(migration).doesNotContain("UPDATE instrument");
            assertThat(migration).doesNotContain("UPDATE market_candle");
            assertThat(migration).doesNotContain("DELETE FROM market_candle");
        }
    }
}
