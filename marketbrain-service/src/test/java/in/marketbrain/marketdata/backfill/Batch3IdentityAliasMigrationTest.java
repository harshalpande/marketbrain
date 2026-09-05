package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class Batch3IdentityAliasMigrationTest {

    @Test
    void migrationAddsOnlyTheThreeReviewedEvidenceBoundedAliases() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V14__add_reviewed_batch3_identity_aliases.sql")) {
            assertThat(stream).isNotNull();
            String migration = new String(stream.readAllBytes(), StandardCharsets.UTF_8);

            assertThat(migration).contains("'CGCL', 'MMFSL', 'INE180C01018'");
            assertThat(migration).contains("'COFORGE', 'NIITTECH', 'INE591G01017'");
            assertThat(migration).contains("'LTFOODS', 'DAAWAT', 'INE818H01012'");
            assertThat(migration).contains("DATE '2011-11-28', DATE '2012-08-07'");
            assertThat(migration).contains("DATE '2020-03-23', DATE '2020-03-25'");
            assertThat(migration).contains("DATE '2013-08-20', DATE '2013-08-20'");
            assertThat(migration).doesNotContain("UPDATE instrument");
            assertThat(migration).doesNotContain("UPDATE market_candle");
            assertThat(migration).doesNotContain("DELETE FROM market_candle");
        }
    }
}
