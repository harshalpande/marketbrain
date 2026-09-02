package in.marketbrain.marketdata.universe;

import org.junit.jupiter.api.Test;

import java.io.StringReader;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CurrentNifty500CsvParserTest {

    private final CurrentNifty500CsvParser parser = new CurrentNifty500CsvParser();

    @Test
    void parsesAnOfficialSizedCurrentSnapshotAndQuotedCompanyName() throws Exception {
        StringBuilder csv = new StringBuilder("Company Name,Industry,Symbol,Series,ISIN Code\n");
        csv.append("\"Example, Industries Ltd.\",Capital Goods,EXAMPLE0,EQ,INE000000000\n");
        for (int index = 1; index < 500; index++) {
            csv.append("Example ").append(index).append(" Ltd.,Industry,SYMBOL")
                    .append(index).append(",EQ,INE").append(String.format("%09d", index)).append('\n');
        }

        var records = parser.parse(new StringReader(csv.toString()));

        assertThat(records).hasSize(500);
        assertThat(records.getFirst().companyName()).isEqualTo("Example, Industries Ltd.");
        assertThat(records.getFirst().isCashEquity()).isTrue();
    }

    @Test
    void rejectsAProviderResponseWithAnImplausibleCount() {
        assertThatThrownBy(() -> parser.parse(new StringReader("""
                Company Name,Industry,Symbol,Series,ISIN Code
                Infosys Limited,IT,INFY,EQ,INE009A01021
                """)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("implausible");
    }

    @Test
    void rejectsAnUnexpectedProviderHeader() {
        assertThatThrownBy(() -> parser.parse(new StringReader("""
                name,symbol,isin
                Infosys Limited,INFY,INE009A01021
                """)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("header");
    }
}
