package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.assertj.core.api.Assertions.assertThat;

class NseBhavcopyParserTest {

    private final NseBhavcopyParser parser = new NseBhavcopyParser();

    @Test
    void parsesLegacyCashMarketRowsAndIgnoresUnsupportedSeries() throws Exception {
        String csv = "SYMBOL,SERIES,OPEN,HIGH,LOW,CLOSE,LAST,PREVCLOSE,TOTTRDQTY,TIMESTAMP,ISIN\n"
                + "ABB,EQ,510.00,520.00,505.00,515.60,515.60,426.35,12345,17-MAY-2013,INE117A01022\n"
                + "ABB,BL,511.00,511.00,511.00,511.00,511.00,426.35,10,17-MAY-2013,INE117A01022\n";

        var records = parser.parse(zip(csv), LocalDate.of(2013, 5, 17));

        assertThat(records).singleElement().satisfies(record -> {
            assertThat(record.symbol()).isEqualTo("ABB");
            assertThat(record.series()).isEqualTo("EQ");
            assertThat(record.previousClose()).isEqualByComparingTo("426.35");
            assertThat(record.close()).isEqualByComparingTo("515.60");
            assertThat(record.volume()).isEqualByComparingTo("12345");
        });
    }

    @Test
    void parsesUdiffRowsIncludingQuotedFields() throws Exception {
        String csv = "TradDt,BizDt,Sgmt,Src,FinInstrmTp,FinInstrmId,ISIN,TckrSymb,SctySrs,"
                + "FinInstrmNm,OpnPric,HghPric,LwPric,ClsPric,LastPric,PrvsClsgPric,TtlTradgVol\n"
                + "2025-01-29,2025-01-29,CM,NSE,STK,123,INE00FF01025,ACUTAAS,EQ,"
                + "\"Acutaas Chemicals, Limited\",940.90,1129.10,930.00,1129.10,1129.10,940.90,50000\n";

        var records = parser.parse(zip(csv), LocalDate.of(2025, 1, 29));

        assertThat(records).singleElement().satisfies(record -> {
            assertThat(record.symbol()).isEqualTo("ACUTAAS");
            assertThat(record.isin()).isEqualTo("INE00FF01025");
            assertThat(record.tradingDate()).isEqualTo(LocalDate.of(2025, 1, 29));
            assertThat(record.open()).isEqualByComparingTo("940.90");
            assertThat(record.close()).isEqualByComparingTo("1129.10");
        });
    }

    private byte[] zip(String csv) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(output, StandardCharsets.UTF_8)) {
            zip.putNextEntry(new ZipEntry("bhavcopy.csv"));
            zip.write(csv.getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();
        }
        return output.toByteArray();
    }
}
