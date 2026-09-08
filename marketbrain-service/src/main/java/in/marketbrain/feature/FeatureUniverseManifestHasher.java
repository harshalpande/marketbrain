package in.marketbrain.feature;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

@Component
class FeatureUniverseManifestHasher {

    String hash(UUID snapshotId, LocalDate asOf, List<FeaturePreview> previews) {
        StringBuilder canonical = new StringBuilder()
                .append(FeaturePreviewService.FEATURE_SET_VERSION).append('|')
                .append(snapshotId).append('|')
                .append(asOf).append('\n');
        for (FeaturePreview preview : previews) {
            canonical.append(preview.symbol()).append('|')
                    .append(preview.status()).append('|')
                    .append(value(preview.effectiveAsOf())).append('|')
                    .append(preview.canonicalObservationCount()).append('|')
                    .append(preview.eligibleObservationCount()).append('|')
                    .append(preview.excludedObservationCount()).append('|');
            appendLatest(canonical, preview.latestCandle());
            appendFeatures(canonical, preview.features());
            canonical.append('\n');
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private void appendLatest(StringBuilder target, FeaturePreview.LatestCandle latest) {
        if (latest == null) {
            target.append("<null>|<null>|<null>|<null>|<null>|<null>|");
            return;
        }
        target.append(value(latest.source())).append('|')
                .append(value(latest.open())).append('|')
                .append(value(latest.high())).append('|')
                .append(value(latest.low())).append('|')
                .append(value(latest.close())).append('|')
                .append(value(latest.volume())).append('|');
    }

    private void appendFeatures(StringBuilder target, FeatureValues features) {
        if (features == null) {
            target.append("<null>");
            return;
        }
        target.append(value(features.previousClose())).append('|')
                .append(value(features.dailyReturnPercent())).append('|')
                .append(value(features.sma20())).append('|')
                .append(value(features.sma50())).append('|')
                .append(value(features.sma200())).append('|')
                .append(value(features.ema12())).append('|')
                .append(value(features.ema26())).append('|')
                .append(value(features.rsi14())).append('|')
                .append(value(features.atr14())).append('|')
                .append(value(features.annualizedVolatility20Percent())).append('|')
                .append(value(features.volumeRatio20())).append('|')
                .append(value(features.rangePosition252Percent()));
    }

    private String value(Object value) {
        if (value == null) {
            return "<null>";
        }
        if (value instanceof BigDecimal decimal) {
            return decimal.toPlainString();
        }
        return value.toString();
    }
}
