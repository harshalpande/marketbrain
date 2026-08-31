package in.marketbrain.marketdata.universe;

import org.junit.jupiter.api.Test;

import java.io.StringReader;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class Nifty500MembershipCsvParserTest {

    private final Nifty500MembershipCsvParser parser = new Nifty500MembershipCsvParser();

    @Test
    void parsesDateEffectiveMembershipAndQuotedCompanyName() throws Exception {
        var records = parser.parse(new StringReader("""
                symbol,isin,companyName,effectiveFrom,effectiveTo
                INFY,INE009A01021,Infosys Limited,2026-01-01,
                ACME,INE000A01001,"Acme, Industries Limited",2026-02-01,2026-07-31
                """));

        assertThat(records).hasSize(2);
        assertThat(records.get(1)).isEqualTo(new Nifty500MembershipRecord(
                "ACME", "INE000A01001", "Acme, Industries Limited",
                LocalDate.of(2026, 2, 1), LocalDate.of(2026, 7, 31)));
    }

    @Test
    void rejectsDuplicateStartOfMembership() {
        assertThatThrownBy(() -> parser.parse(new StringReader("""
                symbol,isin,companyName,effectiveFrom,effectiveTo
                INFY,INE009A01021,Infosys Limited,2026-01-01,
                INFY,INE009A01021,Infosys Limited,2026-01-01,
                """)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Duplicate");
    }

    @Test
    void rejectsFutureMembershipEndBeforeItsStart() {
        assertThatThrownBy(() -> parser.parse(new StringReader("""
                symbol,isin,companyName,effectiveFrom,effectiveTo
                INFY,INE009A01021,Infosys Limited,2026-08-01,2026-07-31
                """)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("effectiveTo");
    }
}
