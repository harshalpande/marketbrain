package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class NseBhavcopyClientTest {

    @Test
    void buildsLegacyArchiveUrlBeforeNseUdiffCutover() {
        assertThat(NseBhavcopyClient.sourceUrl(LocalDate.of(2024, 6, 4)))
                .isEqualTo("https://archives.nseindia.com/content/historical/EQUITIES/2024/JUN/"
                        + "cm04JUN2024bhav.csv.zip");
        assertThat(NseBhavcopyClient.formatFor(LocalDate.of(2024, 6, 4))).isEqualTo("LEGACY");
    }

    @Test
    void buildsUdiffArchiveUrlFromOfficialCutoverDate() {
        assertThat(NseBhavcopyClient.sourceUrl(LocalDate.of(2024, 7, 8)))
                .isEqualTo("https://archives.nseindia.com/content/cm/"
                        + "BhavCopy_NSE_CM_0_0_0_20240708_F_0000.csv.zip");
        assertThat(NseBhavcopyClient.formatFor(LocalDate.of(2024, 7, 8))).isEqualTo("UDIFF");
    }

    @Test
    void downloadsAndParsesOfficialArchiveWithoutPersistingAnything() throws Exception {
        LocalDate date = LocalDate.of(2013, 5, 17);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        var client = new NseBhavcopyClient(builder.build(), new NseBhavcopyParser());
        String csv = "SYMBOL,SERIES,OPEN,HIGH,LOW,CLOSE,LAST,PREVCLOSE,TOTTRDQTY,TIMESTAMP,ISIN\n"
                + "ABB,EQ,510,520,505,515.60,515.60,426.35,12345,17-May-2013,INE117A01022\n";
        server.expect(once(), requestTo(NseBhavcopyClient.sourceUrl(date)))
                .andExpect(header(HttpHeaders.REFERER, "https://www.nseindia.com/all-reports"))
                .andRespond(withSuccess(zip(csv), MediaType.APPLICATION_OCTET_STREAM));

        var result = client.fetch(date);

        assertThat(result.status()).isEqualTo("SUCCESS");
        assertThat(result.records()).singleElement().extracting(NseBhavcopyRecord::symbol).isEqualTo("ABB");
        server.verify();
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
