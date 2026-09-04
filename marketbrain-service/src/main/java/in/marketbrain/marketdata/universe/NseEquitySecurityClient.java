package in.marketbrain.marketdata.universe;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;

@Component
public class NseEquitySecurityClient {

    private final RestClient restClient;
    private final HistoricalBackfillProperties properties;

    public NseEquitySecurityClient(RestClient.Builder builder, HistoricalBackfillProperties properties) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(30));
        this.restClient = builder.requestFactory(requestFactory).build();
        this.properties = properties;
    }

    public NseEquitySecuritySourceResult fetch() {
        try {
            byte[] payload = restClient.get()
                    .uri(properties.nseEquitySecurityUrl())
                    .header("User-Agent", "MarketBrain/0.1 personal-research")
                    .accept(MediaType.parseMediaType("text/csv"), MediaType.APPLICATION_OCTET_STREAM)
                    .retrieve()
                    .body(byte[].class);
            if (payload == null || payload.length == 0) {
                return new NseEquitySecuritySourceResult(
                        "INVALID_SOURCE", null, null, "Official NSE equity security source returned an empty file.");
            }
            return new NseEquitySecuritySourceResult(
                    "SUCCESS", payload, sha256(payload), "Official NSE equity security metadata downloaded.");
        } catch (RestClientException exception) {
            return new NseEquitySecuritySourceResult(
                    "SOURCE_UNAVAILABLE", null, null,
                    "NSE equity security metadata could not be downloaded: " + exception.getClass().getSimpleName());
        }
    }

    private String sha256(byte[] payload) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }
}
