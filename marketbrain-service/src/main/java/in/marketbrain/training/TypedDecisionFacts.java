package in.marketbrain.training;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Arithmetic evidence, not a predictive score or expected answer. No IO or model invocation. */
final class TypedDecisionFacts {
    static final String VERSION = "TYPED_FACTS_V1";

    private TypedDecisionFacts() { }

    static Map<String, String> of(PrototypeSwingOllamaCandidate c) {
        Map<String, String> facts = new LinkedHashMap<>();
        facts.put("factsVersion", VERSION);
        facts.put("sma20", text(c.sma20()));
        facts.put("sma50", text(c.sma50()));
        facts.put("sma200", text(c.sma200()));
        facts.put("ema12", text(c.ema12()));
        facts.put("ema26", text(c.ema26()));
        facts.put("distanceSma20Percent", distance(c.latestClose(), c.sma20()));
        facts.put("distanceSma50Percent", distance(c.latestClose(), c.sma50()));
        facts.put("distanceSma200Percent", distance(c.latestClose(), c.sma200()));
        facts.put("ema12Above26Percent", distance(c.ema12(), c.ema26()));
        facts.put("priceVsAverages", alignment(c));
        facts.put("emaDirection", !positive(c.ema12()) || !positive(c.ema26()) ? "UNKNOWN"
                : c.ema12().compareTo(c.ema26()) > 0 ? "POSITIVE"
                : c.ema12().compareTo(c.ema26()) < 0 ? "NEGATIVE" : "FLAT");
        facts.put("rsiBand", band(c.rsi14(), 40, 70, "BELOW_40", "40_TO_BELOW_70", "AT_LEAST_70"));
        facts.put("volumeBand", band(c.volumeRatio20(), 0.8, 1.2, "BELOW_0_8", "0_8_TO_BELOW_1_2", "AT_LEAST_1_2"));
        facts.put("volatilityBand", band(c.annualizedVolatility20Percent(), 25, 45,
                "BELOW_25", "25_TO_BELOW_45", "AT_LEAST_45"));
        facts.put("rangeBand", band(c.rangePosition252Percent(), 20, 90,
                "BELOW_20", "20_TO_BELOW_90", "AT_LEAST_90"));
        return facts;
    }

    static String distance(BigDecimal value, BigDecimal reference) {
        if (!positive(value) || !positive(reference)) { return "UNKNOWN"; }
        return value.subtract(reference).multiply(BigDecimal.valueOf(100))
                .divide(reference, 2, RoundingMode.HALF_UP).toPlainString();
    }

    static boolean positive(BigDecimal value) { return value != null && value.signum() > 0; }

    private static String text(BigDecimal value) { return value == null ? "UNKNOWN" : value.toPlainString(); }

    private static String alignment(PrototypeSwingOllamaCandidate c) {
        if (!positive(c.latestClose()) || !positive(c.sma20()) || !positive(c.sma50()) || !positive(c.sma200())) {
            return "UNKNOWN";
        }
        var averages = List.of(c.sma20(), c.sma50(), c.sma200());
        if (averages.stream().allMatch(a -> c.latestClose().compareTo(a) > 0)) { return "ABOVE_ALL"; }
        if (averages.stream().allMatch(a -> c.latestClose().compareTo(a) < 0)) { return "BELOW_ALL"; }
        return "MIXED_OR_EQUAL";
    }

    private static String band(BigDecimal value, double low, double high, String below, String middle, String above) {
        if (value == null) { return "UNKNOWN"; }
        return value.compareTo(BigDecimal.valueOf(low)) < 0 ? below
                : value.compareTo(BigDecimal.valueOf(high)) < 0 ? middle : above;
    }

    // Explicit synthetic fixtures, no future labels. These are not held-out investment tests.
    static List<PrototypeSwingOllamaCandidate> contrastCandidates() {
        return List.of(fixture("SYNTHETIC_STRONG", false, "22", "1.4"),
                fixture("SYNTHETIC_WEAK", true, "22", "1.4"),
                fixture("SYNTHETIC_HIGH_VOL", false, "55", "1.4"),
                fixture("SYNTHETIC_MISSING_VOLUME", false, "22", null));
    }

    static List<String> diagnosticExpectations(String symbol) {
        return switch (symbol) {
            case "SYNTHETIC_STRONG" -> List.of("SHORTLIST", "TOP_PICK");
            case "SYNTHETIC_WEAK", "SYNTHETIC_MISSING_VOLUME" -> List.of("REJECT");
            case "SYNTHETIC_HIGH_VOL" -> List.of("WATCHLIST", "SHORTLIST");
            default -> List.of();
        };
    }

    private static PrototypeSwingOllamaCandidate fixture(String symbol, boolean weak, String volatility, String volume) {
        return new PrototypeSwingOllamaCandidate(symbol, LocalDate.of(2026, 6, 5), new BigDecimal("100"),
                new BigDecimal(weak ? "-1" : "1"), new BigDecimal(weak ? "103" : "97"),
                new BigDecimal(weak ? "108" : "94"), new BigDecimal(weak ? "115" : "90"),
                new BigDecimal(weak ? "101" : "99"), new BigDecimal(weak ? "104" : "97"),
                new BigDecimal(weak ? "32" : "58"), new BigDecimal("2"), new BigDecimal(volatility),
                volume == null ? null : new BigDecimal(volume), new BigDecimal(weak ? "15" : "65"),
                null, null, null, null, null, null, null, null, null);
    }
}
