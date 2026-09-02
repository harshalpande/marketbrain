package in.marketbrain.marketdata.upstox;

import java.time.LocalDate;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;

public record UpstoxHistoricalRequest(
        String instrumentKey,
        String unit,
        int interval,
        LocalDate fromDate,
        LocalDate toDate
) {
    private static final Set<String> UNITS = Set.of("minutes", "hours", "days", "weeks", "months");

    public UpstoxHistoricalRequest {
        requireText(instrumentKey, "instrumentKey");
        requireText(unit, "unit");
        unit = unit.toLowerCase(Locale.ROOT);
        if (!UNITS.contains(unit)) {
            throw new IllegalArgumentException("unit must be minutes, hours, days, weeks, or months");
        }
        if (interval < 1) {
            throw new IllegalArgumentException("interval must be positive");
        }
        if (("minutes".equals(unit) && interval > 300)
                || ("hours".equals(unit) && interval > 5)
                || (!"minutes".equals(unit) && !"hours".equals(unit) && interval != 1)) {
            throw new IllegalArgumentException("interval is not supported for the selected unit");
        }
        Objects.requireNonNull(fromDate, "fromDate is required");
        Objects.requireNonNull(toDate, "toDate is required");
        if (toDate.isBefore(fromDate)) {
            throw new IllegalArgumentException("toDate must be on or after fromDate");
        }
        if (fromDate.plusYears(1).isBefore(toDate)) {
            throw new IllegalArgumentException("A manual historical import is limited to one year");
        }
    }

    public String intervalCode() {
        return unit + ":" + interval;
    }

    private static void requireText(String value, String fieldName) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(fieldName + " is required");
        }
    }
}
