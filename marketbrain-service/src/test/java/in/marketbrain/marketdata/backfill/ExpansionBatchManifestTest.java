package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class ExpansionBatchManifestTest {

    private static final UUID SNAPSHOT_ID = UUID.fromString("11111111-2222-3333-4444-555555555555");

    @Test
    void hashIsStableWhenInstrumentInputOrderChanges() {
        var first = instrument("AAA", "NSE_EQ|AAA", LocalDate.of(2012, 1, 1), 15);
        var second = instrument("BBB", "NSE_EQ|BBB", LocalDate.of(2020, 1, 1), 7);

        String original = hash(List.of(first, second));
        String reordered = hash(List.of(second, first));

        assertThat(original).isEqualTo(reordered).hasSize(64);
    }

    @Test
    void hashChangesWhenAReviewedBoundaryChanges() {
        var original = instrument("AAA", "NSE_EQ|AAA", LocalDate.of(2012, 1, 1), 15);
        var changed = instrument("AAA", "NSE_EQ|AAA", LocalDate.of(2013, 1, 1), 14);

        assertThat(hash(List.of(original))).isNotEqualTo(hash(List.of(changed)));
    }

    private String hash(List<ExpansionBatchPreview.Instrument> instruments) {
        return HistoricalBackfillJobService.manifestHash(
                SNAPSHOT_ID, 2, 15, LocalDate.of(2011, 9, 4),
                LocalDate.of(2026, 9, 3), 390, instruments);
    }

    private ExpansionBatchPreview.Instrument instrument(
            String symbol,
            String providerKey,
            LocalDate effectiveFrom,
            int chunks
    ) {
        return new ExpansionBatchPreview.Instrument(
                symbol, providerKey, effectiveFrom, effectiveFrom, chunks);
    }
}
