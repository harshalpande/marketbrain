package in.marketbrain.marketdata.daily;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record DailyEnrichmentPreview(
        UUID universeSnapshotId,
        LocalDate targetDate,
        int instrumentCount,
        int upToDateInstruments,
        int fetchInstruments,
        int blockedInstruments,
        LocalDate earliestFromDate,
        int totalRequestedCalendarDays,
        int maximumCatchupDays,
        String manifestHash,
        boolean databaseWritesPerformed,
        boolean workerEnabled,
        boolean schedulerEnabled,
        String schedulerCron,
        String finalAttemptCron,
        String providerWindowStart,
        String providerWindowCutoff,
        int readinessProbeCount,
        String targetDateFetchMode,
        List<Instrument> instruments,
        String detail
) {
    public DailyEnrichmentPreview {
        instruments = List.copyOf(instruments);
    }

    public record Instrument(
            String symbol,
            String providerInstrumentKey,
            LocalDate lastStoredDate,
            LocalDate requestedFrom,
            LocalDate requestedTo,
            int requestedCalendarDays,
            String status
    ) {
    }
}
