package in.marketbrain.training;

import in.marketbrain.feature.FeatureCandle;
import in.marketbrain.feature.FeatureValues;
import in.marketbrain.feature.TechnicalFeatureCalculator;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Comparator;
import java.util.List;
import java.util.TreeMap;

/** Retrospective, observed-bar features only. Neither an exchange calendar nor a training dataset. */
public final class NumericalFeatureSnapshot {
    public static final String VERSION = "OBSERVED_252_FEATURE_SNAPSHOT_V1";
    public record SourceBar(long candleId, LocalDate date, String source, Instant receivedAt,
            BigDecimal open, BigDecimal high, BigDecimal low, BigDecimal close, BigDecimal volume,
            boolean excluded) {
        FeatureCandle candle() { return new FeatureCandle(date, source, open, high, low, close, volume, excluded); }
    }
    public record Row(LocalDate decisionDate, String status, LocalDate featureFrom,
            int observationCount, int receivedAfterCutoffCount, int missingReceivedAtCount,
            List<Long> sourceCandleIds, FeatureValues features) { }

    public List<SourceBar> canonicalize(List<SourceBar> raw) {
        // Prefer exchange data, then most recently received stored version, then stable candle ID.
        var preference = Comparator.comparingInt((SourceBar b) -> "NSE_BHAVCOPY".equals(b.source()) ? 0 : 1)
                .thenComparing(SourceBar::receivedAt, Comparator.nullsLast(Comparator.reverseOrder()))
                .thenComparing(Comparator.comparingLong(SourceBar::candleId).reversed());
        var dates = new TreeMap<LocalDate, SourceBar>();
        for (var bar : raw) {
            if (bar.date() == null || !("NSE_BHAVCOPY".equals(bar.source()) || "UPSTOX".equals(bar.source()))) {
                throw new IllegalArgumentException("Unknown source or missing date.");
            }
            dates.merge(bar.date(), bar, (a,b) -> preference.compare(a,b) <= 0 ? a : b);
        }
        return List.copyOf(dates.values());
    }

    public Row calculate(LocalDate date, List<SourceBar> canonical, boolean truncated) {
        if (truncated) return blocked(date, "SOURCE_ROW_CAP_EXCEEDED", List.of());
        var available = canonical.stream().filter(b -> !b.date().isAfter(date)).toList();
        if (available.isEmpty() || !available.getLast().date().equals(date)) {
            return blocked(date, "NO_BAR_ON_REQUESTED_DATE", List.of());
        }
        var window = available.subList(Math.max(0, available.size() - 252), available.size());
        if (window.size() < 252) return blocked(date, "INSUFFICIENT_OBSERVATIONS", window);
        // Do not remove an excluded observation and silently substitute an older bar.
        if (window.stream().anyMatch(SourceBar::excluded)) return blocked(date, "EXCLUDED_OBSERVATION", window);
        FeatureValues values;
        try { values = new TechnicalFeatureCalculator().calculate(window.stream().map(SourceBar::candle).toList()); }
        catch (IllegalArgumentException e) { return blocked(date, "INVALID_OBSERVATION", window); }
        if (values.volumeRatio20() == null) return blocked(date, "VOLUME_RATIO_UNAVAILABLE", window);
        return row(date, "FEATURES_ONLY_CALENDAR_UNVERIFIED", window, values);
    }
    private Row blocked(LocalDate date, String status, List<SourceBar> window) { return row(date,status,window,null); }
    private Row row(LocalDate date, String status, List<SourceBar> window, FeatureValues values) {
        var cutoff = date.atTime(16,0).atZone(ZoneId.of("Asia/Kolkata")).toInstant();
        return new Row(date, status, window.isEmpty() ? null : window.getFirst().date(), window.size(),
                (int) window.stream().filter(b -> b.receivedAt() != null && b.receivedAt().isAfter(cutoff)).count(),
                (int) window.stream().filter(b -> b.receivedAt() == null).count(),
                window.stream().map(SourceBar::candleId).toList(), values);
    }
}
