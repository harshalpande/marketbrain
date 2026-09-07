package in.marketbrain.marketdata.daily;

import java.time.LocalDate;
import java.util.List;

public record DailyEnrichmentProviderReadiness(
        LocalDate targetDate,
        String status,
        int requestedChecks,
        int availableChecks,
        int missingChecks,
        int failedChecks,
        List<Check> checks,
        boolean databaseWritesPerformed,
        String detail
) {
    public DailyEnrichmentProviderReadiness {
        checks = List.copyOf(checks);
    }

    public boolean ready() {
        return "READY".equals(status);
    }

    public record Check(String symbol, String status) {
    }
}
