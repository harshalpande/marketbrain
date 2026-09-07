package in.marketbrain.marketdata.upstox;

import java.util.Locale;
import java.util.Objects;
import java.util.Set;

public record UpstoxIntradayRequest(
        String instrumentKey,
        String unit,
        int interval
) {
    private static final Set<String> UNITS = Set.of("minutes", "hours", "days");

    public UpstoxIntradayRequest {
        Objects.requireNonNull(instrumentKey, "instrumentKey is required");
        Objects.requireNonNull(unit, "unit is required");
        if (instrumentKey.isBlank()) {
            throw new IllegalArgumentException("instrumentKey is required");
        }
        unit = unit.toLowerCase(Locale.ROOT);
        if (!UNITS.contains(unit)) {
            throw new IllegalArgumentException("unit must be minutes, hours, or days");
        }
        if (interval < 1
                || ("minutes".equals(unit) && interval > 300)
                || ("hours".equals(unit) && interval > 5)
                || ("days".equals(unit) && interval != 1)) {
            throw new IllegalArgumentException("interval is not supported for the selected unit");
        }
    }

    public String intervalCode() {
        return unit + ":" + interval;
    }
}
