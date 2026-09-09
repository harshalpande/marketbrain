package in.marketbrain.training;

import in.marketbrain.feature.FeaturePreview;
import in.marketbrain.feature.FeatureValues;
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
class SwingTrainingDatasetManifestHasher {

    String hash(
            UUID snapshotId,
            LocalDate asOf,
            LocalDate labelThrough,
            String inputFeatureManifestHash,
            int assumedRoundTripCostBps,
            List<SwingBenchmarkOutcome> benchmarks,
            List<SwingTrainingCohortItem> instruments
    ) {
        StringBuilder canonical = new StringBuilder()
                .append(SwingTrainingDatasetPreviewService.DATASET_CONTRACT_VERSION).append('|')
                .append(snapshotId).append('|')
                .append(asOf).append('|')
                .append(labelThrough).append('|')
                .append(inputFeatureManifestHash).append('|')
                .append(assumedRoundTripCostBps).append('\n');
        for (SwingBenchmarkOutcome benchmark : benchmarks) {
            canonical.append("BENCHMARK|")
                    .append(benchmark.horizonSessions()).append('|')
                    .append(value(benchmark.outcomeDate())).append('|')
                    .append(benchmark.constituentLabelCount()).append('|')
                    .append(value(benchmark.equalWeightGrossReturnPercent())).append('\n');
        }
        for (SwingTrainingCohortItem item : instruments) {
            canonical.append(item.symbol()).append('|')
                    .append(item.status()).append('|')
                    .append(item.missingHorizons()).append('|');
            appendFeature(canonical, item.featureInput());
            for (SwingOutcomeLabel label : item.labels()) {
                canonical.append('|').append(label.horizonSessions()).append('|')
                        .append(label.outcomeDate()).append('|')
                        .append(value(label.grossReturnPercent())).append('|')
                        .append(value(label.assumedRoundTripCostPercent())).append('|')
                        .append(value(label.netReturnPercent())).append('|')
                        .append(value(label.maximumFavorableExcursionPercent())).append('|')
                        .append(value(label.maximumAdverseExcursionPercent())).append('|')
                        .append(value(label.maximumDrawdownPercent())).append('|')
                        .append(value(label.benchmarkProxyReturnPercent())).append('|')
                        .append(value(label.benchmarkExcessReturnPercent()));
            }
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

    private void appendFeature(StringBuilder target, FeaturePreview input) {
        target.append(input.status()).append('|')
                .append(value(input.effectiveAsOf())).append('|')
                .append(input.canonicalObservationCount()).append('|')
                .append(input.eligibleObservationCount()).append('|')
                .append(input.excludedObservationCount()).append('|');
        FeatureValues values = input.features();
        if (values == null) {
            target.append("<null>");
            return;
        }
        target.append(value(values.previousClose())).append('|')
                .append(value(values.dailyReturnPercent())).append('|')
                .append(value(values.sma20())).append('|')
                .append(value(values.sma50())).append('|')
                .append(value(values.sma200())).append('|')
                .append(value(values.ema12())).append('|')
                .append(value(values.ema26())).append('|')
                .append(value(values.rsi14())).append('|')
                .append(value(values.atr14())).append('|')
                .append(value(values.annualizedVolatility20Percent())).append('|')
                .append(value(values.volumeRatio20())).append('|')
                .append(value(values.rangePosition252Percent()));
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
