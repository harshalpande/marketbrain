package in.marketbrain.marketdata.daily;

import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

@Component
public class DailyEnrichmentPlanner {

    public Plan plan(UUID snapshotId, LocalDate targetDate, int maximumCatchupDays, List<Candidate> candidates) {
        if (snapshotId == null || targetDate == null) {
            throw new IllegalArgumentException("Snapshot and target date are required");
        }
        if (maximumCatchupDays < 1) {
            throw new IllegalArgumentException("Maximum catch-up days must be positive");
        }

        List<Candidate> ordered = candidates.stream()
                .sorted(Comparator.comparing(Candidate::symbol)
                        .thenComparing(Candidate::providerInstrumentKey))
                .toList();
        List<DailyEnrichmentPreview.Instrument> previewItems = new ArrayList<>();
        List<PlannedInstrument> fetchItems = new ArrayList<>();
        int upToDate = 0;
        int blocked = 0;
        int totalDays = 0;
        LocalDate earliestFrom = null;

        for (Candidate candidate : ordered) {
            LocalDate requestedFrom = candidate.lastStoredDate() == null
                    ? null : candidate.lastStoredDate().plusDays(1);
            int requestedDays = 0;
            String status;
            if (candidate.lastStoredDate() == null) {
                status = "NO_BASELINE";
                blocked++;
            } else if (requestedFrom.isAfter(targetDate)) {
                status = "UP_TO_DATE";
                upToDate++;
            } else {
                requestedDays = Math.toIntExact(ChronoUnit.DAYS.between(requestedFrom, targetDate) + 1);
                if (requestedDays > maximumCatchupDays) {
                    status = "CATCHUP_LIMIT_EXCEEDED";
                    blocked++;
                } else {
                    status = "FETCH_REQUIRED";
                    fetchItems.add(new PlannedInstrument(candidate.instrumentId(), candidate.providerInstrumentKey(),
                            candidate.symbol(), requestedFrom, targetDate));
                    totalDays += requestedDays;
                    earliestFrom = earliestFrom == null || requestedFrom.isBefore(earliestFrom)
                            ? requestedFrom : earliestFrom;
                }
            }
            previewItems.add(new DailyEnrichmentPreview.Instrument(
                    candidate.symbol(), candidate.providerInstrumentKey(), candidate.lastStoredDate(),
                    requestedFrom, targetDate, requestedDays, status));
        }

        String manifestHash = sha256(canonicalManifest(
                snapshotId, targetDate, maximumCatchupDays, ordered, previewItems));
        DailyEnrichmentPreview preview = new DailyEnrichmentPreview(
                snapshotId, targetDate, ordered.size(), upToDate, fetchItems.size(), blocked,
                earliestFrom, totalDays, maximumCatchupDays, manifestHash, false, false, false, previewItems,
                blocked == 0
                        ? "Read-only incremental plan; no database rows were written."
                        : "Blocked instruments require review before a daily run can be created.");
        return new Plan(snapshotId, preview, fetchItems);
    }

    private String canonicalManifest(
            UUID snapshotId,
            LocalDate targetDate,
            int maximumCatchupDays,
            List<Candidate> candidates,
            List<DailyEnrichmentPreview.Instrument> items
    ) {
        StringBuilder canonical = new StringBuilder()
                .append("DAILY|1|").append(snapshotId).append('|').append(targetDate)
                .append('|').append(maximumCatchupDays).append('\n');
        for (int index = 0; index < candidates.size(); index++) {
            Candidate candidate = candidates.get(index);
            DailyEnrichmentPreview.Instrument item = items.get(index);
            canonical.append(candidate.instrumentId()).append('|')
                    .append(candidate.symbol()).append('|')
                    .append(candidate.providerInstrumentKey()).append('|')
                    .append(value(item.lastStoredDate())).append('|')
                    .append(value(item.requestedFrom())).append('|')
                    .append(item.requestedTo()).append('|')
                    .append(item.status()).append('\n');
        }
        return canonical.toString();
    }

    private String value(LocalDate date) {
        return date == null ? "" : date.toString();
    }

    private String sha256(String value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    public record Candidate(
            long instrumentId,
            String providerInstrumentKey,
            String symbol,
            LocalDate lastStoredDate
    ) {
    }

    public record PlannedInstrument(
            long instrumentId,
            String providerInstrumentKey,
            String symbol,
            LocalDate requestedFrom,
            LocalDate requestedTo
    ) {
    }

    public record Plan(
            UUID snapshotId,
            DailyEnrichmentPreview preview,
            List<PlannedInstrument> fetchItems
    ) {
        public Plan {
            fetchItems = List.copyOf(fetchItems);
        }
    }
}
