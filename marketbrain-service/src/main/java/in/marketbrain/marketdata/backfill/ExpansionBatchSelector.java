package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

@Component
public class ExpansionBatchSelector {

    public Selection select(
            List<Candidate> snapshotInstruments,
            List<String> pilotSymbols,
            Set<Long> completedExpansionInstrumentIds,
            int batchSize
    ) {
        if (batchSize < 1) {
            throw new IllegalArgumentException("Expansion batch size must be positive");
        }
        Set<String> excludedSymbols = new HashSet<>();
        pilotSymbols.forEach(symbol -> excludedSymbols.add(symbol.trim().toUpperCase(Locale.ROOT)));

        List<Candidate> remaining = snapshotInstruments.stream()
                .filter(candidate -> !excludedSymbols.contains(candidate.symbol().toUpperCase(Locale.ROOT)))
                .filter(candidate -> !completedExpansionInstrumentIds.contains(candidate.instrumentId()))
                .sorted(Comparator.comparing(Candidate::symbol).thenComparingLong(Candidate::instrumentId))
                .toList();
        List<Candidate> selected = remaining.stream().limit(batchSize).toList();
        return new Selection(selected, remaining.size() - selected.size());
    }

    public record Candidate(long instrumentId, String providerInstrumentKey, String symbol, LocalDate listedOn) {
    }

    public record Selection(List<Candidate> selected, int remainingAfterBatch) {
        public Selection {
            selected = List.copyOf(selected);
        }
    }
}
