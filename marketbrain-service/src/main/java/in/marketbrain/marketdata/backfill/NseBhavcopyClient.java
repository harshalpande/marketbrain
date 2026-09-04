package in.marketbrain.marketdata.backfill;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import java.io.IOException;
import java.time.Duration;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

@Component
class NseBhavcopyClient {

    static final LocalDate UDIFF_START_DATE = LocalDate.of(2024, 7, 8);
    private static final String BASE_URL = "https://archives.nseindia.com";
    private static final String REPORTS_PAGE = "https://www.nseindia.com/all-reports";
    private static final DateTimeFormatter LEGACY_MONTH = DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH);
    private static final DateTimeFormatter LEGACY_FILE_DATE = DateTimeFormatter.ofPattern("ddMMMyyyy", Locale.ENGLISH);
    private static final DateTimeFormatter UDIFF_FILE_DATE = DateTimeFormatter.BASIC_ISO_DATE;

    private final RestClient restClient;
    private final NseBhavcopyParser parser;

    @Autowired
    NseBhavcopyClient(RestClient.Builder builder, NseBhavcopyParser parser) {
        this(configuredClient(builder), parser);
    }

    NseBhavcopyClient(RestClient restClient, NseBhavcopyParser parser) {
        this.restClient = restClient;
        this.parser = parser;
    }

    NseBhavcopyArchive fetch(LocalDate tradingDate) {
        String format = formatFor(tradingDate);
        String sourceUrl = sourceUrl(tradingDate);
        try {
            byte[] body = restClient.get()
                    .uri(sourceUrl)
                    .header(HttpHeaders.USER_AGENT,
                            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MarketBrain/0.1 evidence-verifier")
                    .header(HttpHeaders.REFERER, REPORTS_PAGE)
                    .accept(MediaType.APPLICATION_OCTET_STREAM)
                    .retrieve()
                    .body(byte[].class);
            List<NseBhavcopyRecord> records = parser.parse(body, tradingDate);
            return new NseBhavcopyArchive(
                    "SUCCESS", tradingDate, format, sourceUrl, records,
                    "Official NSE Bhavcopy was read for evidence only; no data was persisted or changed.");
        } catch (RestClientResponseException exception) {
            int statusCode = exception.getStatusCode().value();
            String status = statusCode == 404 ? "SOURCE_NOT_FOUND"
                    : statusCode == 429 ? "RATE_LIMITED"
                    : statusCode >= 500 ? "SOURCE_UNAVAILABLE" : "SOURCE_REJECTED";
            return NseBhavcopyArchive.failure(
                    status, tradingDate, format, sourceUrl,
                    "NSE rejected the read-only Bhavcopy request with HTTP " + statusCode + ".");
        } catch (RestClientException exception) {
            return NseBhavcopyArchive.failure(
                    "CONNECTION_FAILED", tradingDate, format, sourceUrl,
                    "NSE could not be reached; this evidence request can be retried safely.");
        } catch (IOException exception) {
            return NseBhavcopyArchive.failure(
                    "INVALID_SOURCE_ARCHIVE", tradingDate, format, sourceUrl,
                    "NSE returned a Bhavcopy archive that could not be parsed safely.");
        }
    }

    static String sourceUrl(LocalDate tradingDate) {
        if (tradingDate.isBefore(UDIFF_START_DATE)) {
            String month = LEGACY_MONTH.format(tradingDate).toUpperCase(Locale.ENGLISH);
            String fileDate = LEGACY_FILE_DATE.format(tradingDate).toUpperCase(Locale.ENGLISH);
            return BASE_URL + "/content/historical/EQUITIES/" + tradingDate.getYear() + "/" + month
                    + "/cm" + fileDate + "bhav.csv.zip";
        }
        return BASE_URL + "/content/cm/BhavCopy_NSE_CM_0_0_0_"
                + UDIFF_FILE_DATE.format(tradingDate) + "_F_0000.csv.zip";
    }

    static String formatFor(LocalDate tradingDate) {
        return tradingDate.isBefore(UDIFF_START_DATE) ? "LEGACY" : "UDIFF";
    }

    private static RestClient configuredClient(RestClient.Builder builder) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(30));
        return builder.requestFactory(requestFactory).build();
    }
}
