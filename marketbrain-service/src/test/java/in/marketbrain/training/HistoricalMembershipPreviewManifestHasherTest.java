package in.marketbrain.training;

import in.marketbrain.marketdata.universe.Nifty500MembershipRecord;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class HistoricalMembershipPreviewManifestHasherTest {

    private final HistoricalMembershipPreviewManifestHasher hasher =
            new HistoricalMembershipPreviewManifestHasher();

    @Test
    void producesAnOrderIndependentLowercaseManifest() {
        var first = new Nifty500MembershipRecord(
                "INFY", "INE009A01021", "Infosys Limited",
                LocalDate.of(2026, 4, 1), null);
        var second = new Nifty500MembershipRecord(
                "TCS", "INE467B01029", "Tata Consultancy Services Limited",
                LocalDate.of(2026, 4, 1), null);
        var firstMatch = new HistoricalMembershipMemberPreview(
                first.symbol(), first.isin(), first.companyName(), first.effectiveFrom(), null,
                "MATCHED", 1L, "INFY", "CURRENT_ISIN");
        var secondMatch = new HistoricalMembershipMemberPreview(
                second.symbol(), second.isin(), second.companyName(), second.effectiveFrom(), null,
                "MATCHED", 2L, "TCS", "CURRENT_ISIN");

        String forward = hasher.hash(
                LocalDate.of(2026, 6, 5), "Official source", "https://example.test/source.csv",
                "a".repeat(64), List.of(first, second), List.of(firstMatch, secondMatch));
        String reversed = hasher.hash(
                LocalDate.of(2026, 6, 5), "Official source", "https://example.test/source.csv",
                "a".repeat(64), List.of(second, first), List.of(secondMatch, firstMatch));

        assertThat(forward).matches("[0-9a-f]{64}").isEqualTo(reversed);
    }
}
