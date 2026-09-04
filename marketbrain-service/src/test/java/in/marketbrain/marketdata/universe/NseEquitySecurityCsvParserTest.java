package in.marketbrain.marketdata.universe;

import org.junit.jupiter.api.Test;

import java.io.StringReader;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class NseEquitySecurityCsvParserTest {

    private final NseEquitySecurityCsvParser parser = new NseEquitySecurityCsvParser();

    @Test
    void parsesOfficialHeaderDatesAndQuotedNames() throws Exception {
        StringBuilder csv = header();
        csv.append("RECENT,\"Recent, Industries Limited\", BE,05-OCT-2020,10,1,INE000000000,10\n");
        for (int index = 1; index < 500; index++) {
            csv.append("SYMBOL").append(index).append(",Company ").append(index)
                    .append(",EQ,01-JAN-2000,10,1,INE")
                    .append(String.format("%09d", index)).append(",10\n");
        }

        var records = parser.parse(new StringReader(csv.toString()));

        assertThat(records).hasSize(500);
        assertThat(records.getFirst().companyName()).isEqualTo("Recent, Industries Limited");
        assertThat(records.getFirst().series()).isEqualTo("BE");
        assertThat(records.getFirst().listedOn()).isEqualTo(LocalDate.of(2020, 10, 5));
    }

    @Test
    void acceptsGovernedCashEquitySeriesAndIgnoresUnrelatedSeries() throws Exception {
        StringBuilder csv = header();
        csv.append("BESEC,BE Security,BE,01-JAN-2000,10,1,INE000000000,10\n");
        csv.append("BZSEC,BZ Security,BZ,01-JAN-2000,10,1,INE000000001,10\n");
        csv.append("SMESEC,SME Security,SM,01-JAN-2000,10,1,INE000000002,10\n");
        for (int index = 3; index < 501; index++) {
            csv.append("SYMBOL").append(index).append(",Company ").append(index)
                    .append(",EQ,01-JAN-2000,10,1,INE")
                    .append(String.format("%09d", index)).append(",10\n");
        }

        var records = parser.parse(new StringReader(csv.toString()));

        assertThat(records).hasSize(500);
        assertThat(records).extracting(NseEquitySecurity::symbol)
                .contains("BESEC", "BZSEC")
                .doesNotContain("SMESEC");
    }

    @Test
    void rejectsAnInvalidListingDate() {
        assertThatThrownBy(() -> parser.parse(new StringReader(
                header() + "RECENT,Recent Limited,EQ,31-FEB-2020,10,1,INE000000000,10\n")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("DATE OF LISTING");
    }

    @Test
    void rejectsAChangedHeader() {
        assertThatThrownBy(() -> parser.parse(new StringReader("symbol,isin,date\n")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("header");
    }

    private StringBuilder header() {
        return new StringBuilder(
                "SYMBOL,NAME OF COMPANY, SERIES, DATE OF LISTING, PAID UP VALUE, MARKET LOT, ISIN NUMBER, FACE VALUE\n");
    }
}
