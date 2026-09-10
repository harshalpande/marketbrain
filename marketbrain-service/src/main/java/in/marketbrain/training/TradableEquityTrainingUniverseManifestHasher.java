package in.marketbrain.training;

import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;

@Component
public class TradableEquityTrainingUniverseManifestHasher {

    public String hash(
            String contractVersion,
            LocalDate asOf,
            int minimumEligibleObservations,
            List<TradableEquityTrainingUniverseItem> instruments
    ) {
        StringBuilder canonical = new StringBuilder();
        canonical.append(contractVersion).append('\n')
                .append(asOf).append('\n')
                .append(minimumEligibleObservations).append('\n');
        for (TradableEquityTrainingUniverseItem instrument : instruments) {
            canonical.append(instrument.instrumentId()).append('|')
                    .append(instrument.symbol()).append('|')
                    .append(nullToEmpty(instrument.isin())).append('|')
                    .append(instrument.status()).append('|')
                    .append(nullToEmpty(instrument.firstCandleDate())).append('|')
                    .append(nullToEmpty(instrument.latestCandleDate())).append('|')
                    .append(instrument.canonicalObservationCount()).append('|')
                    .append(instrument.eligibleObservationCount()).append('|')
                    .append(instrument.excludedObservationCount()).append('|')
                    .append(nullToEmpty(instrument.latestSource())).append('\n');
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }

    private String nullToEmpty(Object value) {
        return value == null ? "" : value.toString();
    }
}
