package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class InstrumentIdentityAliasMigrationTest {

    @Test
    void migrationAddsEvidenceBackedAliasesWithoutRewritingInstrumentsOrCandles() throws IOException {
        String migration = migrationText();

        assertThat(migration).contains("CREATE TABLE instrument_identity_alias");
        assertThat(migration).contains("'ACUTAAS', 'AMIORG', 'INE00FF01017'");
        assertThat(migration).contains("DATE '2025-04-25'");
        assertThat(migration).contains("CML67615.pdf");
        assertThat(migration).contains("CML68201.pdf");
        assertThat(migration).doesNotContain("UPDATE instrument");
        assertThat(migration).doesNotContain("UPDATE market_candle");
        assertThat(migration).doesNotContain("DELETE FROM market_candle");
    }

    private String migrationText() throws IOException {
        try (InputStream stream = getClass().getResourceAsStream(
                "/db/migration/V11__create_instrument_identity_aliases.sql")) {
            assertThat(stream).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
