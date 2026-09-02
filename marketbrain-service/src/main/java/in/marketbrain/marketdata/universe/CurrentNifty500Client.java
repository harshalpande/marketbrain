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
public class CurrentNifty500Client {

    private final RestClient restClient;
    private final HistoricalBackfillProperties properties;

    public CurrentNifty500Client(RestClient.Builder builder, HistoricalBackfillProperties properties) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(Duration.ofSeconds(30));
        this.restClient = builder.requestFactory(requestFactory).build();
        this.properties = properties;
    }

    public Nifty500SourceResult fetch() {
        try {
            byte[] payload = restClient.get()
                    .uri(properties.currentNifty500Url())
                    .header("User-Agent", "MarketBrain/0.1 personal-research")
                    .accept(MediaType.parseMediaType("text/csv"), MediaType.APPLICATION_OCTET_STREAM)
                    .retrieve()
                    .body(byte[].class);
            if (payload == null || payload.length == 0) {
                return new Nifty500SourceResult("INVALID_SOURCE", null, null,
                        "Official current NIFTY 500 source returned an empty file.");
            }
            return new Nifty500SourceResult("SUCCESS", payload, sha256(payload),
                    "Official current NIFTY 500 snapshot downloaded.");
        } catch (RestClientException exception) {
            return new Nifty500SourceResult("SOURCE_UNAVAILABLE", null, null,
                    "Current NIFTY 500 source could not be downloaded: " + exception.getClass().getSimpleName());
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
